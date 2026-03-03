//
//  Store.swift
//  FluxExample
//
//
//  このファイルは Flux アーキテクチャにおける Store の “基底クラス” を提供している。
//  Store は Flux の中心概念であり、主な責務は次の2つである。
//
//  1) Dispatcher から Action を受け取り（購読）
//  2) Action に応じて内部の State を更新し、その変更を View に通知する
//
//  Flux の単方向フローを再掲するとこうなる。
//
//      View（ユーザ操作）
//           ↓
//      ActionCreator（副作用 + Action生成）
//           ↓ dispatch(Action)
//      Dispatcher（配信）
//           ↓
//      Store（Actionを解釈して State を更新）   ← ★ここ
//           ↓ emitChange
//      View（State を購読し再描画）
//
//  本クラス Store は “State の具体形” を持たず、
//  - Dispatcher に登録して Action を受け取る仕組み
//  - View が購読するための変更通知（storeChanged）
//  だけを提供する。
//  実際の state 更新はサブクラスが onDispatch を override して実装する。
//
//  React/Redux の用語に寄せると、Store は reducer を内包し、emitChange は subscribe の通知に相当する。
//

import Foundation

// MARK: - Subscription
//
// Store の変更通知を購読したときに返ってくるトークン型。
// NotificationCenter.addObserver(forName:using:) の戻り値（NSObjectProtocol）をそのまま用いている。
// View 側はこの Subscription を保持し、不要になったら removeListener で解除する。
typealias Subscription = NSObjectProtocol

// MARK: - Store (Base Class)
//
// class にしているのは、Flux で Store を継承して具体 Store を作る設計のため。
//（例: SearchStore, FavoriteStore など）
//
// この基底 Store が提供するもの:
// - Dispatcher への登録/解除（dispatchToken 管理）
// - Store変更通知の発火（emitChange）
// - View からの購読/解除（addListener/removeListener）
class Store {

    // MARK: - Notification Name (Store -> View)
    //
    // Store の state が変化したことを View に伝えるための通知名。
    // static に閉じておくことで外部から勝手に post されることを防ぐ。
    private enum NotificationName {
        static let storeChanged = Notification.Name("store-changed")
    }

    // MARK: - Dispatcher registration token
    //
    // Dispatcher.register の戻り値を保持しておき、deinit で unregister するためのトークン。
    //
    // lazy で初期化している理由:
    // - init 内で self をキャプチャするクロージャが必要になる
    // - self.dispatcher が初期化された後に register したい
    //
    // register すると Dispatcher から Action が流れてくるようになり、
    // callback 内で onDispatch(action) が呼ばれる。
    private lazy var dispatchToken: DispatchToken = {
        return dispatcher.register(callback: { [weak self] action in
            // weak self: Store が解放された後に Dispatcher から callback が飛んできても
            // クラッシュしないようにする（循環参照も避ける）。
            self?.onDispatch(action)
        })
    }()

    // MARK: - Dependencies

    /// Action の配信ハブ。
    /// Store はここに登録して Action を受け取る。
    private let dispatcher: Dispatcher

    /// Store の変更通知を流すための NotificationCenter。
    /// default を使わず Store 専用の NotificationCenter を持つことで、
    /// 通知のスコープを “この Store の購読者” に閉じられる。
    private let notificationCenter: NotificationCenter

    // MARK: - Deinit

    /// Store が破棄されるときに Dispatcher から unregister する。
    ///
    /// これを忘れると、解放済み Store に Action が流れ続けたり、
    /// token が残ってメモリリーク的な挙動になる可能性がある。
    deinit {
        dispatcher.unregister(dispatchToken)
    }

    // MARK: - Init

    /// Store の初期化。
    ///
    /// - dispatcher: Action の配信元
    ///
    /// init の最後で `_ = dispatchToken` しているのが重要ポイント。
    /// これは lazy プロパティの初期化を強制し、Store 作成と同時に Dispatcher 登録を完了させるため。
    ///
    /// つまり、
    /// - Store が生成された瞬間から Action を受け取れる状態になる
    /// という契約を作っている。
    init(dispatcher: Dispatcher) {
        self.dispatcher = dispatcher
        self.notificationCenter = NotificationCenter()

        // lazy の dispatchToken をここで強制初期化して、Dispatcher に登録する。
        // これをしないと、dispatchToken が初めて参照されるまで register されず、
        // Action を受け取れないタイミングが発生し得る。
        _ = dispatchToken
    }

    // MARK: - Action handling (Reducer entry point)

    /// Dispatcher から Action が流れてきたときに呼ばれる。
    ///
    /// サブクラスで override し、Action に応じて state を更新する（reducer 相当）。
    /// 更新後に View を再描画させたい場合は emitChange() を呼ぶ。
    ///
    /// 本基底クラスでは “必ず override しろ” という契約のため fatalError にしている。
    func onDispatch(_ action: Action) {
        fatalError("must override")
    }

    // MARK: - Emit change (Store -> View)

    /// state が変化したことを購読者（View）へ通知する。
    ///
    /// Flux の subscribe 通知に相当する。
    /// View は addListener で購読し、通知を受けたら Store の state を読み直して描画更新する。
    final func emitChange() {
        notificationCenter.post(name: NotificationName.storeChanged, object: nil)
    }

    // MARK: - Subscription API (View subscribe/unsubscribe)

    /// Store の変更を購読する。
    ///
    /// - callback: Store が変化したときに呼ばれる（通常は View の再描画を行う）
    /// - returns: Subscription（解除に必要）
    ///
    /// NotificationCenter.addObserver の token を返しているため、View 側はそれを保持し、
    /// 画面破棄時などに removeListener(subscription) で解除する。
    final func addListener(callback: @escaping () -> ()) -> Subscription {

        // NotificationCenter の using クロージャは Notification を受け取る。
        // ここでは通知名を確認して callback を呼ぶ。
        // （forName で絞っているので name チェックは冗長だが、保険として残している可能性がある）
        let using: (Notification) -> () = { notification in
            if notification.name == NotificationName.storeChanged {
                callback()
            }
        }

        // queue: nil にしているため、通知が post されたスレッドで callback が実行される。
        // UI更新をするなら main thread で emitChange する（もしくは View 側で main に戻す）設計が必要。
        return notificationCenter.addObserver(forName: NotificationName.storeChanged,
                                              object: nil,
                                              queue: nil,
                                              using: using)
    }

    /// 購読解除。
    /// addListener が返した Subscription を渡して解除する。
    final func removeListener(_ subscription: Subscription) {
        notificationCenter.removeObserver(subscription)
    }
}