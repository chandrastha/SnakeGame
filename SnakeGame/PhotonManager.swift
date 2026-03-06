//
//  PhotonManager.swift
//  SnakeGame
//
//  Online multiplayer back-end — Firebase Realtime Database.
//  Public interface (RemotePlayerState, PhotonManagerDelegate, PhotonManager singleton
//  with identical method signatures) is unchanged so GameScene and ContentView
//  require minimal integration glue.
//
//  SETUP — do these once before first build:
//  1. console.firebase.google.com → create project → add iOS app (bundle ID from Xcode)
//  2. Authentication → Sign-in method → enable Anonymous
//  3. Realtime Database → Create database (test mode or use rules below)
//  4. Project Settings → download GoogleService-Info.plist → drag into Xcode, add to target
//  5. Xcode → File → Add Package Dependencies →
//       https://github.com/firebase/firebase-ios-sdk
//       add products: FirebaseDatabase  FirebaseAuth
//
//  Firebase Database Rules (paste in console → Database → Rules tab):
//  {
//    "rules": {
//      ".read":  "auth != null",
//      ".write": "auth != null"
//    }
//  }
//  NOTE: rules must allow read at the root level so the room-list query works.
//

import Foundation
import Combine
import FirebaseCore
import FirebaseDatabase
import FirebaseAuth

// MARK: - Shared data types (used by GameScene — must not change shape)

/// Snapshot of a remote player's snake, delivered via the delegate.
struct RemotePlayerState {
    let headX:      Float
    let headY:      Float
    let angle:      Float
    let score:      Int
    let bodyLength: Int
    let playerName: String
}

// MARK: - Delegate (GameScene conforms to this)

protocol PhotonManagerDelegate: AnyObject {
    func didJoinRoom()
    func didReceivePlayerState(_ state: RemotePlayerState, playerID: Int)
    func didReceiveFoodEaten(foodIndex: Int, newFoodX: Float, newFoodY: Float, newFoodType: Int)
    func didPlayerLeave(playerID: Int)
    func didReceiveOpponentDied(playerID: Int)
}

// MARK: - Connection state (drives OnlineMatchView)

extension PhotonManager {
    enum ConnectionState {
        case disconnected
        case connecting
        case inLobby
        case inRoom
        case failed
    }
}

// MARK: - PhotonManager

/// Singleton that wraps Firebase Realtime Database for online snake multiplayer.
/// All public method signatures match the original Photon-stub API exactly.
final class PhotonManager: NSObject, ObservableObject {

    // ─────────────────────────────────────────────────────────────────
    // PASTE YOUR DATABASE URL HERE
    // Firebase console → Realtime Database → Data tab
    // The URL is shown at the very top in grey text, e.g.:
    //   https://viperun-12345-default-rtdb.firebaseio.com/
    // Copy it (without the trailing slash) and replace the placeholder below.
    // ─────────────────────────────────────────────────────────────────
    private static let firebaseDatabaseURL =
        "https://viperun-24854-default-rtdb.firebaseio.com/"

    // MARK: Singleton
    static let shared = PhotonManager()
    private override init() { super.init() }

    // MARK: Published (drives OnlineMatchView UI)
    @Published var connectionState: ConnectionState = .disconnected
    @Published var roomPlayerCount: Int = 0
    /// Human-readable description of the last error — shown in OnlineMatchView.
    @Published var lastError: String = ""

    // MARK: Delegate (GameScene)
    weak var delegate: PhotonManagerDelegate? {
        didSet { replayCurrentRoomStateIfNeeded() }
    }

    // MARK: Firebase refs
    // Uses the explicit URL above so it works even if GoogleService-Info.plist
    // was downloaded before the Realtime Database was created.
    private lazy var db: DatabaseReference = {
        Database.database(url: Self.firebaseDatabaseURL).reference()
    }()
    private var roomRef:      DatabaseReference?
    private var myPlayerRef:  DatabaseReference?
    private var playersRef:   DatabaseReference?
    private var foodRef:      DatabaseReference?

    // MARK: Room state
    private var roomId:  String = ""
    private var myUID:   String = ""

    // MARK: Observer handles (for cleanup)
    private var handlePlayerAdded:   DatabaseHandle?
    private var handlePlayerChanged: DatabaseHandle?
    private var handlePlayerRemoved: DatabaseHandle?
    private var handleFoodAdded:     DatabaseHandle?
    private var handleFoodChanged:   DatabaseHandle?
    private var handlePlayerCount:   DatabaseHandle?

    // MARK: Local player name (set before connect())
    private var localPlayerName: String = "Player"

    /// Call this before connect() so the name is broadcast to other players in the room.
    func setPlayerName(_ name: String) {
        localPlayerName = name.isEmpty ? "Player" : name
    }

    // MARK: Actor-ID mapping  (Firebase UID string → stable Int for GameScene)
    private var playerIDMap:  [String: Int] = [:]
    private var nextActorID:  Int = 1

    // MARK: Watchdog (fail visibly if Firebase never responds)
    private var roomSearchWatchdog: DispatchWorkItem?
    private var pendingPlayerRemovalWorkItem: DispatchWorkItem?
    private var connectionAttemptID: UInt = 0

    // MARK: Cached room state (replayed when GameScene attaches after lobby join)
    private var latestRemotePlayers: [Int: RemotePlayerState] = [:]
    private var latestFoodSlots: [Int: (x: Float, y: Float, type: Int)] = [:]

    // MARK: - Connect / Disconnect

    /// Authenticate anonymously with Firebase, then immediately search for / create a room.
    /// Calling this again while already connecting / in a room is a no-op.
    func connect() {
        guard AppFeatureFlags.isOnlineModeEnabled else {
            DispatchQueue.main.async {
                self.lastError = "Online mode is disabled in this build."
                self.connectionState = .failed
            }
            return
        }
        guard connectionState == .disconnected || connectionState == .failed else { return }
        connectionAttemptID &+= 1
        let attemptID = connectionAttemptID
        DispatchQueue.main.async { self.connectionState = .connecting }

        Auth.auth().signInAnonymously { [weak self] result, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.connectionAttemptID == attemptID else { return }
                if let uid = result?.user.uid {
                    self.myUID = uid
                    self.connectionState = .inLobby
                    // Immediately start room search — don't rely on an external timer
                    self.joinOrCreateRoom(attemptID: attemptID)
                } else {
                    let msg = error?.localizedDescription ?? "Anonymous sign-in failed"
                    print("[PhotonManager] Auth failed: \(msg)")
                    self.lastError = "Auth: \(msg)"
                    self.connectionState = .failed
                }
            }
        }
    }

    /// Sign out and tear down everything.
    func disconnect() {
        connectionAttemptID &+= 1
        leaveRoom()
        try? Auth.auth().signOut()
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.roomPlayerCount = 0
        }
    }

    // MARK: - Room management

    /// Find an open room (playerCount < maxPlayers) or create a new one.
    func joinOrCreateRoom(maxPlayers: Int = 100) {
        joinOrCreateRoom(maxPlayers: maxPlayers, attemptID: connectionAttemptID)
    }

    private func joinOrCreateRoom(maxPlayers: Int = 100, attemptID: UInt) {
        guard connectionState == .inLobby, !myUID.isEmpty else { return }

        // Watchdog: if Firebase never responds within 10 s, surface the failure.
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self = self, self.connectionState == .inLobby else { return }
            let msg = "Timed out — check: Realtime Database exists in Firebase console, rules allow auth != null reads, and GoogleService-Info.plist is added to the target."
            print("[PhotonManager] \(msg)")
            self.lastError = msg
            self.connectionState = .failed
        }
        roomSearchWatchdog?.cancel()
        roomSearchWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watchdog)

        // observeSingleEvent WITH withCancel:
        //   • Waits for the Firebase WebSocket to establish before querying
        //     (unlike getData which fails immediately if the socket isn't open yet)
        //   • withCancel surfaces permission-denied / network errors
        db.child("rooms")
            .queryOrdered(byChild: "playerCount")
            .queryStarting(atValue: 1)
            .queryEnding(atValue: maxPlayers - 1)
            .queryLimited(toFirst: 1)
            .observeSingleEvent(of: .value, with: { [weak self] snapshot in
                guard let self = self else { return }
                guard self.connectionAttemptID == attemptID else { return }
                self.roomSearchWatchdog?.cancel()

                if let firstRoom = snapshot.children.allObjects.first as? DataSnapshot {
                    // Found a room with space — join it
                    self.joinExistingRoom(roomId: firstRoom.key, maxPlayers: maxPlayers, attemptID: attemptID)
                } else {
                    // No room available — create a new one
                    self.createRoom(maxPlayers: maxPlayers, attemptID: attemptID)
                }
            }, withCancel: { [weak self] error in
                guard let self = self else { return }
                guard self.connectionAttemptID == attemptID else { return }
                self.roomSearchWatchdog?.cancel()
                let msg = error.localizedDescription
                print("[PhotonManager] Room query failed: \(msg)")
                DispatchQueue.main.async {
                    self.lastError = "DB query: \(msg)"
                    self.connectionState = .failed
                }
            })
    }

    /// Leave the current room and return to lobby state.
    func leaveRoom() {
        connectionAttemptID &+= 1
        guard !roomId.isEmpty || myPlayerRef != nil || roomRef != nil else {
            DispatchQueue.main.async {
                self.roomPlayerCount = 0
                self.connectionState = .disconnected
            }
            return
        }

        roomSearchWatchdog?.cancel()
        roomSearchWatchdog = nil
        pendingPlayerRemovalWorkItem?.cancel()
        pendingPlayerRemovalWorkItem = nil
        removeAllObservers()

        // Cancel disconnect hooks so a manual leave does not apply a second decrement.
        myPlayerRef?.cancelDisconnectOperations()
        roomRef?.child("playerCount").cancelDisconnectOperations()

        // Remove own player node
        myPlayerRef?.removeValue()

        // Decrement player count (with floor at 0)
        if !roomId.isEmpty {
            db.child("rooms/\(roomId)/playerCount").runTransactionBlock { currentData in
                let count = max(0, (currentData.value as? Int ?? 1) - 1)
                currentData.value = count
                return TransactionResult.success(withValue: currentData)
            }
        }

        // Reset refs & state
        roomRef      = nil
        myPlayerRef  = nil
        playersRef   = nil
        foodRef      = nil
        roomId       = ""
        playerIDMap  = [:]
        nextActorID  = 1
        latestRemotePlayers.removeAll()
        latestFoodSlots.removeAll()

        DispatchQueue.main.async {
            self.roomPlayerCount = 0
            self.connectionState = .disconnected
        }
    }

    // MARK: - Game events (called by GameScene)

    /// Signal that the local snake is ready.
    func sendGameReady() {
        pendingPlayerRemovalWorkItem?.cancel()
        pendingPlayerRemovalWorkItem = nil
        myPlayerRef?.child("gameReady").setValue(true)
    }

    /// Broadcast local snake position at up to ~15 Hz.
    func sendPlayerState(headX: Float, headY: Float, angle: Float,
                         score: Int, bodyLength: Int) {
        pendingPlayerRemovalWorkItem?.cancel()
        pendingPlayerRemovalWorkItem = nil
        myPlayerRef?.updateChildValues([
            "headX":      headX,
            "headY":      headY,
            "angle":      angle,
            "score":      score,
            "bodyLength": bodyLength,
            "alive":      true,
            "playerName": localPlayerName
        ])
    }

    /// Broadcast that the local player ate a food item (syncs position for all clients).
    func sendFoodEaten(foodIndex: Int, newFoodX: Float, newFoodY: Float, newFoodType: Int) {
        foodRef?.child("\(foodIndex)").setValue([
            "x":    newFoodX,
            "y":    newFoodY,
            "type": newFoodType
        ])
    }

    /// Broadcast that the local snake died; removes own node from Firebase.
    func sendPlayerDied() {
        pendingPlayerRemovalWorkItem?.cancel()
        myPlayerRef?.updateChildValues(["alive": false])
        // Short delay so remote clients see the death flag, then remove
        let workItem = DispatchWorkItem { [weak self] in
            self?.myPlayerRef?.removeValue()
            self?.pendingPlayerRemovalWorkItem = nil
        }
        pendingPlayerRemovalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Recreate the local player node for an online restart before the next countdown begins.
    func prepareLocalPlayerForNewRound() {
        pendingPlayerRemovalWorkItem?.cancel()
        pendingPlayerRemovalWorkItem = nil
        myPlayerRef?.setValue(initialLocalPlayerPayload())
    }

    // MARK: - Private helpers

    private func createRoom(maxPlayers: Int, attemptID: UInt) {
        let newRef = db.child("rooms").childByAutoId()
        let id = newRef.key ?? UUID().uuidString

        newRef.setValue([
            "playerCount": 1,
            "maxPlayers":  maxPlayers,
            "status":      "waiting",
            "createdAt":   ServerValue.timestamp(),
            "hostUID":     myUID,
            "food":        Self.initialRoomFoodSeed()
        ]) { [weak self] error, _ in
            guard let self = self else { return }
            guard self.connectionAttemptID == attemptID else {
                newRef.removeValue()
                return
            }
            if error == nil {
                self.enterRoom(roomId: id, attemptID: attemptID)
            } else {
                let msg = error!.localizedDescription
                print("[PhotonManager] createRoom failed: \(msg)")
                DispatchQueue.main.async {
                    self.lastError = "Create room: \(msg)"
                    self.connectionState = .failed
                }
            }
        }
    }

    private func joinExistingRoom(roomId: String, maxPlayers: Int, attemptID: UInt) {
        // Atomically increment playerCount
        db.child("rooms/\(roomId)/playerCount").runTransactionBlock { currentData in
            let count = currentData.value as? Int ?? 0
            if count >= maxPlayers {
                return TransactionResult.abort()  // room filled up between query and join
            }
            currentData.value = count + 1
            return TransactionResult.success(withValue: currentData)
        } andCompletionBlock: { [weak self] error, committed, _ in
            guard let self = self else { return }
            guard self.connectionAttemptID == attemptID else {
                if committed {
                    self.db.child("rooms/\(roomId)/playerCount").runTransactionBlock { currentData in
                        let count = max(0, (currentData.value as? Int ?? 1) - 1)
                        currentData.value = count
                        return TransactionResult.success(withValue: currentData)
                    }
                }
                return
            }
            if let error {
                let msg = error.localizedDescription
                print("[PhotonManager] joinExistingRoom failed: \(msg)")
                DispatchQueue.main.async {
                    self.lastError = "Join room: \(msg)"
                    self.connectionState = .failed
                }
            } else if committed {
                self.enterRoom(roomId: roomId, attemptID: attemptID)
            } else {
                // Room was full — create a new one instead
                self.createRoom(maxPlayers: maxPlayers, attemptID: attemptID)
            }
        }
    }

    private func enterRoom(roomId: String, attemptID: UInt) {
        guard connectionAttemptID == attemptID else { return }
        self.roomId  = roomId
        roomRef      = db.child("rooms/\(roomId)")
        myPlayerRef  = roomRef?.child("players/\(myUID)")
        playersRef   = roomRef?.child("players")
        foodRef      = roomRef?.child("food")

        // Write own initial state
        myPlayerRef?.setValue(initialLocalPlayerPayload())

        // Clean up own node if the device disconnects unexpectedly
        myPlayerRef?.onDisconnectRemoveValue()
        db.child("rooms/\(roomId)/playerCount").onDisconnectSetValue(
            ServerValue.increment(-1)
        )

        // Observe live player count for UI/debug visibility
        handlePlayerCount = roomRef?.child("playerCount").observe(.value) { [weak self] snapshot in
            let count = snapshot.value as? Int ?? 0
            DispatchQueue.main.async { self?.roomPlayerCount = count }
        }

        // Start real-time observers
        startObservingPlayers()
        startObservingFood()

        DispatchQueue.main.async {
            guard self.connectionAttemptID == attemptID else { return }
            self.connectionState = .inRoom
            self.replayCurrentRoomStateIfNeeded()
        }
    }

    private func initialLocalPlayerPayload() -> [String: Any] {
        [
            "headX": Float(2000),
            "headY": Float(2000),
            "angle": Float(0),
            "score": 0,
            "bodyLength": 3,
            "alive": true,
            "uid": myUID,
            "playerName": localPlayerName,
            "gameReady": false
        ]
    }

    // MARK: Players observer

    private func startObservingPlayers() {
        // New player joined (also fires for existing players on first attach)
        handlePlayerAdded = playersRef?.observe(.childAdded) { [weak self] snapshot in
            self?.handlePlayerSnapshot(snapshot, event: .added)
        }

        // An existing player updated their state
        handlePlayerChanged = playersRef?.observe(.childChanged) { [weak self] snapshot in
            self?.handlePlayerSnapshot(snapshot, event: .changed)
        }

        // A player disconnected / left
        handlePlayerRemoved = playersRef?.observe(.childRemoved) { [weak self] snapshot in
            guard let self = self, snapshot.key != self.myUID else { return }
            let actorID = self.actorID(for: snapshot.key)
            self.latestRemotePlayers.removeValue(forKey: actorID)
            DispatchQueue.main.async {
                self.delegate?.didPlayerLeave(playerID: actorID)
            }
        }
    }

    private enum PlayerEvent { case added, changed }

    private func handlePlayerSnapshot(_ snapshot: DataSnapshot, event: PlayerEvent) {
        // Ignore own node
        guard snapshot.key != myUID else { return }
        guard let data = snapshot.value as? [String: Any] else { return }

        let actorID = actorID(for: snapshot.key)
        let alive   = data["alive"] as? Bool ?? true
        let providedName = data["playerName"] as? String
        let remoteName = (providedName?.isEmpty == false)
            ? (providedName ?? "Player \(actorID)")
            : "Player \(actorID)"
        let state   = RemotePlayerState(
            headX:      (data["headX"]      as? NSNumber)?.floatValue ?? 0,
            headY:      (data["headY"]      as? NSNumber)?.floatValue ?? 0,
            angle:      (data["angle"]      as? NSNumber)?.floatValue ?? 0,
            score:      (data["score"]      as? Int) ?? 0,
            bodyLength: (data["bodyLength"] as? Int) ?? 3,
            playerName: remoteName
        )

        if alive {
            latestRemotePlayers[actorID] = state
        } else {
            latestRemotePlayers.removeValue(forKey: actorID)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if alive {
                self.delegate?.didReceivePlayerState(state, playerID: actorID)
            } else {
                self.delegate?.didReceiveOpponentDied(playerID: actorID)
            }
        }
    }

    // MARK: Food observer

    private func startObservingFood() {
        handleFoodAdded = foodRef?.observe(.childAdded) { [weak self] snapshot in
            self?.handleFoodSnapshot(snapshot)
        }

        handleFoodChanged = foodRef?.observe(.childChanged) { [weak self] snapshot in
            self?.handleFoodSnapshot(snapshot)
        }
    }

    private func handleFoodSnapshot(_ snapshot: DataSnapshot) {
        guard let data = snapshot.value as? [String: Any],
              let index = Int(snapshot.key) else { return }

        let newX  = (data["x"]    as? NSNumber)?.floatValue ?? 0
        let newY  = (data["y"]    as? NSNumber)?.floatValue ?? 0
        let type  = (data["type"] as? Int) ?? 0
        latestFoodSlots[index] = (newX, newY, type)

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceiveFoodEaten(
                foodIndex: index, newFoodX: newX, newFoodY: newY, newFoodType: type
            )
        }
    }

    // MARK: Observer cleanup

    private func removeAllObservers() {
        if let h = handlePlayerAdded   { playersRef?.removeObserver(withHandle: h) }
        if let h = handlePlayerChanged { playersRef?.removeObserver(withHandle: h) }
        if let h = handlePlayerRemoved { playersRef?.removeObserver(withHandle: h) }
        if let h = handleFoodAdded     { foodRef?.removeObserver(withHandle: h) }
        if let h = handleFoodChanged   { foodRef?.removeObserver(withHandle: h) }
        if let h = handlePlayerCount   { roomRef?.child("playerCount").removeObserver(withHandle: h) }
        handlePlayerAdded   = nil
        handlePlayerChanged = nil
        handlePlayerRemoved = nil
        handleFoodAdded     = nil
        handleFoodChanged   = nil
        handlePlayerCount   = nil
    }

    // MARK: Room replay

    private func replayCurrentRoomStateIfNeeded() {
        guard connectionState == .inRoom, let delegate else { return }

        DispatchQueue.main.async {
            delegate.didJoinRoom()

            for index in self.latestFoodSlots.keys.sorted() {
                guard let food = self.latestFoodSlots[index] else { continue }
                delegate.didReceiveFoodEaten(
                    foodIndex: index,
                    newFoodX: food.x,
                    newFoodY: food.y,
                    newFoodType: food.type
                )
            }

            for actorID in self.latestRemotePlayers.keys.sorted() {
                guard let state = self.latestRemotePlayers[actorID] else { continue }
                delegate.didReceivePlayerState(state, playerID: actorID)
            }
        }
    }

    // MARK: Initial room food

    static func initialRoomFoodSeed(
        count: Int = 200,
        worldSize: Float = 4000,
        padding: Float = 80
    ) -> [String: [String: Any]] {
        var food: [String: [String: Any]] = [:]
        var shieldCount = 0

        for index in 0..<count {
            let type = randomSpawnFoodType(activeShieldCount: &shieldCount)
            food["\(index)"] = [
                "x": Float.random(in: padding...(worldSize - padding)),
                "y": Float.random(in: padding...(worldSize - padding)),
                "type": type
            ]
        }

        return food
    }

    private static func randomSpawnFoodType(activeShieldCount: inout Int) -> Int {
        let roll = Int.random(in: 0...99)
        let type: FoodType

        switch roll {
        case 0...89:  type = .regular
        case 90...91: type = activeShieldCount < 2 ? .shield : .regular
        case 92...93: type = .multiplier
        case 94...95: type = .magnet
        case 96...97: type = .ghost
        default:      type = .shrink
        }

        if type == .shield { activeShieldCount += 1 }
        return type.rawValue
    }

    // MARK: UID → stable Int actor ID

    private func actorID(for uid: String) -> Int {
        if let id = playerIDMap[uid] { return id }
        let id = nextActorID
        playerIDMap[uid] = id
        nextActorID += 1
        return id
    }
}
