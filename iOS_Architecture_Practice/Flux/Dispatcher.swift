//
//  Dispatcher.swift
//  FluxExample
//
//
//  このファイルは Flux アーキテクチャにおける Dispatcher を実装している。
//  Dispatcher は “Action 配信ハブ” であり、ActionCreator が dispatch した Action を
//  登録済みの Store（やその他の購読者）へ一斉配信する役割を持つ。
//
//  Flux の単方向データフローでは Dispatcher は次の位置にある。
//
//      View（ユーザ操作）
//           ↓
//      ActionCreator（副作用 + Action生成）
//           ↓ dispatch(Action)
//      Dispatcher（Actionを配信）            ← ★このファイル
//           ↓
//      Store（Actionを解釈して State更新）
//           ↓
//      View（Stateを描画）
//
//  Dispatcher 自体は “状態” を持たない（本質的にはイベントルータ）。
//  ただし実装としては、どの購読者に配信するかを管理するため、
//  - callbacks（購読者一覧）
//  - register/unregister（購読管理）
//  を持つ。
//
//  また、Flux 実装で重要なのが “スレッド安全性” と “再入可能性” である。
//  - 複数スレッドから register/unregister/dispatch が呼ばれても壊れない
//  - dispatch 中に別の dispatch が起きてもデッドロックしない（再入可能）
//  そのため本実装では NSRecursiveLock を使っている。
//

import Foundation

// MARK: - DispatchToken
//
// register した購読者を識別するためのトークン。
// Store 側はこの token を保持し、破棄時に unregister(token) して購読解除する。
typealias DispatchToken = String

// MARK: - Dispatcher
//
// final: 継承でロック戦略や配信順が変わると Flux 全体の挙動が壊れやすいので固定する。
// shared を提供しているため、アプリ内で単一 Dispatcher を共有する設計（典型的な Flux）。
final class Dispatcher {

    // MARK: Shared instance

    /// アプリ内で共有する Dispatcher。
    /// ActionCreator / Store が同じ Dispatcher を参照することで、
//  「1つの配信ハブ」に Action が集約される。
    static let shared = Dispatcher()

    // MARK: Concurrency control

    /// 排他制御用ロック。
    /// NSLocking プロトコルで抽象化しているが、実体は NSRecursiveLock。
    ///
    /// NSRecursiveLock を使う理由（重要）:
    /// - dispatch 中に callback がさらに dispatch を呼ぶ（再入）可能性がある
    /// - 普通の NSLock だと同一スレッドで再度 lock しようとしてデッドロックする
    ///
    /// Flux 実装では Store の onDispatch 内で別 Action を dispatch する設計は避けることが多いが、
    /// “念のため再入可能” にしておくと安全側に倒せる。
    let lock: NSLocking

    // MARK: Subscribers (callbacks)

    /// 購読者（Store 等）のコールバック一覧。
    /// key: DispatchToken（購読ID）
    /// value: (Action) -> Void（Action を受け取ったときの処理）
    ///
    /// dispatch(action) が呼ばれると、この callbacks のすべてに action を渡して通知する。
    private var callbacks: [DispatchToken: (Action) -> ()]

    // MARK: Init

    /// 初期化。
    /// callbacks は空で開始する。
    /// lock は NSRecursiveLock を使用し、register/unregister/dispatch をスレッド安全にする。
    init() {
        self.lock = NSRecursiveLock()
        self.callbacks = [:]
    }

    // MARK: Register

    /// 購読登録。
    ///
    /// - Parameter callback: Action を受け取ったときに呼び出される関数（通常は Store.onDispatch）
    /// - Returns: DispatchToken（解除に必要）
    ///
    /// アルゴリズム:
    /// 1) lock を取る（callbacks の同時アクセスを防ぐ）
    /// 2) UUID でユニークな token を生成する
    /// 3) callbacks[token] = callback として登録する
    /// 4) token を返す
    ///
    /// 注意:
    /// - token を Store 側が保持し、deinit 等で unregister するのがセット
    func register(callback: @escaping (Action) -> ()) -> DispatchToken {
        lock.lock(); defer { lock.unlock() }

        // UUID を token として使うことで衝突しづらい一意なIDを得る。
        let token = UUID().uuidString

        // token をキーに callback を保存する。
        callbacks[token] = callback
        return token
    }

    // MARK: Unregister

    /// 購読解除。
    ///
    /// - Parameter token: register 時に返された token
    ///
    /// アルゴリズム:
    /// 1) lock を取る
    /// 2) callbacks から token の entry を削除する
    ///
    /// 解除しないと callback が残り続け、Store が解放されない/解放後に呼ばれる等の事故が起こりうる。
    func unregister(_ token: DispatchToken) {
        lock.lock(); defer { lock.unlock() }

        callbacks.removeValue(forKey: token)
    }

    // MARK: Dispatch

    /// Action を購読者へ配信する。
    ///
    /// - Parameter action: 発生したイベント（ActionCreator が生成したもの）
    ///
    /// アルゴリズム:
    /// 1) lock を取る（callbacks の走査中に register/unregister が走って壊れるのを防ぐ）
    /// 2) callbacks に登録されているすべての callback を列挙する
    /// 3) callback(action) を順に呼び出す（ブロードキャスト）
    ///
    /// 重要な注意点（Flux設計上の勘所）:
    /// - ここは同期的に全購読者を呼ぶ実装である
    ///   → ある Store の処理が重いと dispatch 全体が遅くなる
    /// - lock を持ったまま callback を呼んでいる
    ///   → callback の中で register/unregister/dispatch を呼ぶと再入しうる（NSRecursiveLock なのでデッドロックは回避）
    ///   → ただし設計としては “dispatch 中に callbacks を弄る” のは複雑になりやすい
    ///
    /// 実務的には、次の改善が検討されることが多い:
    /// - lock 内で callbacks のスナップショット（配列）を作り、lock を外してから callback を呼ぶ
    ///   → 長時間 lock を保持しない/副作用の連鎖を抑えられる
    /// - dispatch を main thread に限定する（UI更新を安全にする）
    func dispatch(_ action: Action) {
        lock.lock(); defer { lock.unlock() }

        // 登録済みの全購読者へ Action を配信する。
        callbacks.forEach { _, callback in
            callback(action)
        }
    }
}