//
//  Dispatcher.swift
//  FluxWithRxSwift
//
//  この Dispatcher は Flux アーキテクチャにおける “アクションの配送（dispatch）” を担う。
//  RxSwift（正確には RxCocoa の PublishRelay）を使って、
//  「Action が発行されたら、登録済みの購読者（Storeなど）へ配信する」仕組みを実装している。
//
//  Flux の基本:
//    View(ユーザ操作) → ActionCreator → Dispatcher → Store → View(表示更新)
//
//  Dispatcher の役割は “中央集権的な配信所” であり、
//  - Action を受け取って（dispatch）
//  - 登録している全ての購読者に同じ Action を配る（broadcast）
//  という一点に責務を絞るのが典型である。
//
//  RxSwift を使う意義:
//  - Action を Observable のイベントとして扱える
//  - Store 側は subscribe するだけで “Action を受け取る” ことができる
//  - Disposable によって購読解除（unregister）を明確に扱える
//
//  なおこの実装は、前に出てきた “クロージャ配列 + ロック” の Dispatcher を
//  Rx のストリームで置き換えたものだと捉えると理解しやすい。
//

import RxCocoa
import RxSwift

// MARK: - Dispatcher
//
// Flux の “単一 Dispatcher” を想定した実装。
// static shared でグローバル共有しているため、どこからでも dispatch できる。
// （利便性は高いが、テスト容易性の観点では DI できる形の方が扱いやすいことも多い）
final class Dispatcher {

    /// アプリ内で唯一の Dispatcher を想定したシングルトン。
    /// Flux の世界観では「Action は必ず Dispatcher を通る」ため、こういう形がよく採用される。
    static let shared = Dispatcher()

    // MARK: - Action Stream (Rx)

    /// Action を流すための Relay。
    ///
    /// PublishRelay の性質:
    /// - Observable として購読できる
    /// - accept(_) で next イベントを流す（onNext）
    /// - onError / onCompleted が存在しない（イベントストリームが終端しない）
    ///
    /// Flux の Dispatcher は “途中で完了しない配信所” として扱うのが自然なので、
    /// PublishRelay を使うのは相性が良い。
    ///
    /// PublishSubject との違い（重要）:
    /// - PublishSubject は onError / onCompleted があり、誤って終わる可能性がある
    /// - PublishRelay は error/completed を流せないので “死なないストリーム” になる
    ///
    /// つまり Dispatcher の安定性（運用上の事故回避）を型で担保している。
    private let _action = PublishRelay<Action>()

    // MARK: - Init

    /// init は公開されているが、基本は shared を使う想定。
    /// ただし、ユニットテストでは “専用の Dispatcher インスタンス” を作れるので、
    /// shared 固定よりは少しテストに優しい。
    init() {}

    // MARK: - Register (subscribe)

    /// Dispatcher に購読者を登録する。
    ///
    /// 引数:
    /// - callback: Action を受け取ったときに呼ばれる処理（通常は Store の onDispatch など）
    ///
    /// 戻り値:
    /// - Disposable: 購読解除のためのハンドル。
    ///   Store の deinit や disposeBag に入れて管理することで、
    ///   購読が残り続けてリークする事故を防げる。
    ///
    /// アルゴリズム:
    /// 1) _action を subscribe する
    /// 2) onNext に callback をそのまま渡す
    /// 3) subscribe が返す Disposable を返す
    ///
    /// 注意:
    /// - subscribe した callback は、dispatch が呼ばれるたびに呼ばれる。
    /// - 呼ばれるスレッドは “dispatch が accept を呼んだスレッド” に依存する。
    ///   UI更新をするなら observeOn(MainScheduler.instance) を Store 側で検討する。
    func register(callback: @escaping (Action) -> ()) -> Disposable {
        return _action.subscribe(onNext: callback)
    }

    // MARK: - Dispatch (emit)

    /// Action を Dispatcher に流す。
    ///
    /// アルゴリズム:
    /// 1) _action.accept(action) を呼ぶ
    /// 2) accept により “next イベント” が発行される
    /// 3) register で購読している全購読者の callback が順に呼ばれる（broadcast）
    ///
    /// これにより Flux の「すべての Action は Dispatcher を経由して Store に届く」
    /// という一方向データフローが成立する。
    ///
    /// 注意（スレッド）:
    /// - accept は呼び出しスレッドで動くので、
    ///   どのスレッドから dispatch しているかはアプリ側で統一するのが安全。
    /// - 例えば “ActionCreator は必ずメインスレッドで dispatch” などの規約を作るか、
    ///   Dispatcher 側で MainScheduler へ寄せる設計も考えられる。
    func dispatch(_ action: Action) {
        _action.accept(action)
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) Dispatcher を DI 可能にする
//    - shared 固定は便利だがテストで差し替えにくい。
//    - 各 ActionCreator/Store に DispatcherProtocol を注入する設計が定番。
//
// 2) スケジューラ方針を決める
//    - “dispatch は常にメイン”
//    - “dispatch はどこでも良いが Store 側で observeOn(MainScheduler)”
//    など、UI更新と整合する規約を作ると事故が減る。
//
// 3) デバッグ用途のロギング
//    - dispatch 時に Action をログ出しすると Flux の追跡が非常に楽になる。
//    - Rx なら do(onNext:) を噛ませるだけで実現できる。
//
// 4) Action ストリームの公開方法
//    - register(callback:) ではなく action: Observable<Action> を公開し、
//      Store 側が subscribe する方式もよくある。
//      例: var action: Observable<Action> { _action.asObservable() }
//```