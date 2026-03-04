//
//  SearchRepositoryStore.swift
//  FluxWithRxSwift
//
//  このファイルは Flux アーキテクチャにおける Store（状態管理）を実装している。
//  Dispatcher から流れてくる Action を購読し、Action に応じて内部の State を更新する。
//  さらに、更新された State を
//    - “現在値（value）として参照できる API”
//    - “Observable として購読できる API”
//  の両方で外部に公開している。
//
//  位置づけ（Flux）:
//    View（UI）
//      ↓ ユーザ操作
//    ActionCreator（Action生成 + dispatch）
//      ↓ Action
//    Dispatcher（配信）
//      ↓ Action
//    Store（State更新）  ← ここ
//      ↓ Stateの変化
//    View（購読してUI更新）
//
//  Rx を使う Store の狙い:
//  - State を BehaviorRelay に置くことで “最新値” を保持できる
//  - State の変更を Observable として外部へ配信できる
//  - UI は subscribe するだけで更新イベントを受け取れる
//
//  この実装は、以前の “NotificationCenter を使って StoreChanged を投げる Store” を
//  Rx の State ストリームで置き換えた形だと考えると理解しやすい。
//

import GitHub
import RxCocoa
import RxSwift

// MARK: - SearchRepositoryStore
//
// SearchRepository（リポジトリ検索）画面に必要な状態を管理する Store。
// 典型的には
// - 検索クエリ
// - ページネーション情報
// - 検索中フラグ
// - 検索フィールド編集中フラグ
// - 取得済みのリポジトリ一覧
// - エラー
// など “UI が表示するための状態” をまとめて持つ。
final class SearchRepositoryStore {

    /// 単一 Store を想定したシングルトン。
    /// Flux では Store は複数あってよいが、ここでは検索用 Store を1つ共有する設計。
    static let shared = SearchRepositoryStore()

    // MARK: - State (private relays)

    /// 現在の検索クエリ。
    /// BehaviorRelay は「最新値を保持しつつ、変更イベントも流せる」ため Store の状態に向く。
    private let _query = BehaviorRelay<String?>(value: nil)

    /// 現在のページネーション情報（次ページがあるか等）。
    private let _pagination = BehaviorRelay<GitHub.Pagination?>(value: nil)

    /// 検索フィールドを編集中かどうか。
    /// UI の表示切り替え（例: 検索候補表示）などで使う想定。
    private let _isSearchFieldEditing = BehaviorRelay<Bool>(value: false)

    /// リポジトリ検索 API を実行中かどうか。
    /// ローディング表示などで使う想定。
    private let _isFetching = BehaviorRelay<Bool>(value: false)

    /// 取得済みリポジトリ一覧（検索結果）。
    /// ページングで追加取得する場合は append していく。
    private let _repositories = BehaviorRelay<[GitHub.Repository]>(value: [])

    /// エラーは “最新値として保持したい” とは限らないため PublishRelay を使う。
    /// - BehaviorRelay だと「最後のエラー」が残り続ける（画面再表示時に再発火等の問題）
    /// - PublishRelay は “イベントとして流すだけ” に向いている
    private let _error = PublishRelay<Error>()

    // MARK: - Rx Lifetime

    /// Store が Dispatcher を購読するための DisposeBag。
    /// Store が生存している間購読を維持し、Store が解放されると購読も破棄される。
    private let disposeBag = DisposeBag()

    // MARK: - Init

    /// Dispatcher から Action を購読し、Action に応じて State を更新する。
    ///
    /// アルゴリズム（Store の核）:
    /// 1) dispatcher.register で Action ストリームを購読する
    /// 2) Action を switch で分類する（Reducer 的な処理）
    /// 3) 対応する State Relay に accept して状態更新する
    ///
    /// ここでの設計上のポイント:
    /// - “Action → State 更新” のみを Store の責務にしている（副作用を持たない）
    /// - ActionCreator が dispatch する順序を信頼し、Store は受け取った順に反映する
    /// - self は weak でキャプチャし、Store の解放後にコールバックが生き残らないようにする
    ///
    /// 注意（スレッド）:
    /// - dispatcher がどのスレッドで Action を流すかによって、ここも同じスレッドで動く。
    /// - UI が購読して UI 更新するなら、UI 側で MainScheduler へ寄せるか、
    ///   dispatch をメインスレッドに統一する方針が必要。
    init(dispatcher: Dispatcher = .shared) {

        dispatcher.register(callback: { [weak self] action in

            // Store は通常アプリ全体で生存する想定だが、念のため self が消えていたら何もしない。
            guard let me = self else {
                return
            }

            // “Reducer” 的な処理：
            // Action を見て、どの State をどう更新するかを決める。
            switch action {

            // 検索結果が届いた：
            // ページングを想定して、既存の repositories に追加する（append）。
            // ここが “全置換” ではなく “追加” になっている点が重要で、
            // ActionCreator が page 取得を繰り返すと検索結果が蓄積される。
            case let .searchRepositories(repositories):
                me._repositories.accept(me._repositories.value + repositories)

            // 検索結果のクリア：
            // 新しい検索を始めるときなどに呼ばれ、一覧を空にする。
            case .clearSearchRepositories:
                me._repositories.accept([])

            // ページネーション情報の更新：
            // “次のページがあるか” 等の情報を State として保持する。
            case let .searchPagination(pagination):
                me._pagination.accept(pagination)

            // フェッチ中フラグ更新：
            // ローディング表示制御のための状態。
            case let .isRepositoriesFetching(isFetching):
                me._isFetching.accept(isFetching)

            // 検索フィールド編集中フラグ更新：
            // UI のモード切替（入力中/確定後）等で使える。
            case let .isSearchFieldEditing(isEditing):
                me._isSearchFieldEditing.accept(isEditing)

            // エラーイベント：
            // エラーは “状態” として保持するというより “イベント” として通知する設計。
            case let .error(error):
                me._error.accept(error)

            // 検索クエリ更新：
            // 検索バーに入っている文字列や、確定した query を Store が保持する。
            case let .searchQuery(query):
                me._query.accept(query)

            // この Store の管轄外の Action：
            // （例）お気に入り、選択状態などは別 Store が担当する想定。
            // Flux では「Store は関心のある Action だけ処理し、他は無視する」のが基本。
            case .selectedRepository,
                 .setFavoriteRepositories:
                return
            }
        })
        // register は Disposable を返すので、DisposeBag に入れて購読ライフサイクルを Store に紐付ける。
        .disposed(by: disposeBag)
    }
}

// MARK: - Values（現在値の取得 API）
//
// UI が “最新の状態を同期的に参照したい” ときに使う。
// 例: cellForRow で repositories を使うなど。
// ただし、Rx を主軸にするなら View は Observable を購読して状態を受け取る方が一貫しやすい。
extension SearchRepositoryStore {

    /// 現在保持している検索結果一覧（最新値）。
    var repositories: [GitHub.Repository] {
        return _repositories.value
    }

    /// 現在のページネーション情報（最新値）。
    var pagination: GitHub.Pagination? {
        return _pagination.value
    }

    /// 検索フィールドを編集中か（最新値）。
    var isSearchFieldEditing: Bool {
        return _isSearchFieldEditing.value
    }

    /// フェッチ中か（最新値）。
    var isFetching: Bool {
        return _isFetching.value
    }

    /// 現在のクエリ（最新値）。
    var query: String? {
        return _query.value
    }
}

// MARK: - Observables（変更イベントの購読 API）
//
// UI が “状態の変更” をリアクティブに受け取りたいときに使う。
// 典型例:
//   store.repositoriesObservable
//     .observe(on: MainScheduler.instance)
//     .bind(to: tableView.rx.items(...))
// のように購読して UI を更新する。
extension SearchRepositoryStore {

    /// 検索結果一覧の変更を購読する。
    /// BehaviorRelay なので、購読時点で最新値も流れてくる（初回に現在値が流れる）。
    var repositoriesObservable: Observable<[GitHub.Repository]> {
        return _repositories.asObservable()
    }

    /// ページネーション情報の変更を購読する。
    var paginationObservable: Observable<GitHub.Pagination?> {
        return _pagination.asObservable()
    }

    /// 検索フィールド編集中フラグの変更を購読する。
    var isSearchFieldEditingObservable: Observable<Bool> {
        return _isSearchFieldEditing.asObservable()
    }

    /// フェッチ中フラグの変更を購読する。
    var isFetchingObservable: Observable<Bool> {
        return _isFetching.asObservable()
    }

    /// 検索クエリの変更を購読する。
    var queryObservable: Observable<String?> {
        return _query.asObservable()
    }

    /// エラーイベントの購読。
    /// PublishRelay なので “イベントとして流れるだけ” で、購読開始時に過去のエラーは流れない。
    var errorObservable: Observable<Error> {
        return _error.asObservable()
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) Reducer っぽい関数に分離する
//    - init の switch が肥大化しやすいので
//      func reduce(action: Action) { ... } に切り出すと読みやすい。
//
// 2) append の重複対策
//    - ページングで同じ repository が混ざるケースがあるなら
//      id で unique 化する等のポリシーが必要。
//    - “クリア→取得→追加” の順序保証も ActionCreator 側と合わせる必要がある。
//
// 3) スレッド方針の明文化
//    - Store が accept するスレッドと UI が購読するスレッドを統一する。
//    - UI は observe(on: MainScheduler.instance) を徹底するのが一般的。
//
// 4) error の取り扱い（状態 vs イベント）
//    - “最後のエラーを表示し続ける” なら BehaviorRelay<Error?> が向く。
//    - “発生したらトースト表示して終わり” なら PublishRelay が向く。
//    方針を画面単位で揃えると事故が減る。
//```