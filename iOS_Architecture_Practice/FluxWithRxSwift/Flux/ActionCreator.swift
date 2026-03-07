//
//  ActionCreator.swift
//  FluxWithRxSwift
//
//
//  このファイルは Flux + RxSwift 構成における ActionCreator を実装している。
//  ActionCreator の役割は、ユーザ操作や外部イベントを受けて
//
//  1. 必要なら副作用を実行する
//     - API 通信
//     - ローカルキャッシュの読み書き
//
//  2. その結果を Action として Dispatcher に流す
//
//  ことである。
//
//  Flux の基本データフローは次の通りである。
//
//    View
//      ↓ ユーザ操作
//    ActionCreator
//      ↓ dispatch(Action)
//    Dispatcher
//      ↓
//    Store
//      ↓ 状態更新
//    View
//
//  このファイルは「副作用の起点」と「Action 発行の順序制御」を担当している。
//  特に RxSwift を導入したことで、API 通信結果を Observable として受け取り、
//  subscribe の中で Action を dispatch する流れになっている。
//
//  重要な設計ポイント:
//  - Store は状態更新だけを担当する
//  - ActionCreator は副作用を担当する
//  - View は ActionCreator を呼ぶだけに寄せる
//
//  これにより責務分離が明確になる。
//

import GitHub

// MARK: - ActionCreator
//
// Flux における ActionCreator 本体。
// ここでは状態は持たず、必要な依存を受け取って
// 「何を dispatch するか」を決定する役割に徹する。
final class ActionCreator {

    // MARK: - Dependencies

    /// Action を配信するための Dispatcher。
    /// ActionCreator はここに対して dispatch を行う。
    ///
    /// デフォルトでは shared を使っているため、アプリ全体で同一 Dispatcher を共有する構成。
    /// 実務ではテストしやすさのため Protocol 化して DI することも多い。
    private let dispatcher: Dispatcher

    /// GitHub API への通信を行う抽象。
    /// searchRepositories(...) が Observable を返す想定。
    ///
    /// ActionCreator は通信の中身を知らず、
    /// 「検索すると repositories と pagination が返ってくる」という契約だけを使う。
    private let apiSession: GitHubApiRequestable

    /// ローカルキャッシュ抽象。
    /// お気に入り一覧の保存・取得に使う。
    ///
    /// UserDefaults やファイル保存など、実体が何であるかは ActionCreator から見えない。
    private let localCache: LocalCacheable

    // MARK: - Init

    /// 依存注入。
    ///
    /// デフォルト引数によって、通常利用では shared 実装をそのまま使える。
    /// 一方、テスト時にはモック/スタブを注入して副作用を制御できる。
    init(dispatcher: Dispatcher = .shared,
         apiSession: GitHubApiRequestable = GitHubApiSession.shared,
         localCache: LocalCacheable = LocalCache.shared) {
        self.dispatcher = dispatcher
        self.apiSession = apiSession
        self.localCache = localCache
    }
}

// MARK: - Search
//
// 検索機能に関する Action 発行群。
// 検索系ユースケースでは
// - query の更新
// - loading 開始/終了
// - API 結果
// - エラー
// を Action として順番に流すことが重要になる。
extension ActionCreator {

    /// リポジトリ検索を行う。
    ///
    /// アルゴリズム:
    /// 1. 検索クエリを Store に反映する
    /// 2. ローディング開始を通知する
    /// 3. API 通信を開始する
    /// 4. 成功したら repositories と pagination を dispatch する
    /// 5. 最後にローディング終了を dispatch する
    /// 6. 失敗したら error を dispatch し、ローディング終了も dispatch する
    ///
    /// ここでの重要点:
    /// - View は API 成功/失敗を直接知らない
    /// - Store は Action を受けて状態を更新するだけ
    /// - ActionCreator が「副作用の前後でどの Action を出すか」を決めている
    ///
    /// RxSwift 観点:
    /// - apiSession.searchRepositories(...) は Observable を返す
    /// - take(1) により最初の 1 イベントだけ受け取り、その後購読を終了する
    /// - subscribe(onNext:onError:) で成功/失敗を分岐する
    func searchRepositories(query: String, page: Int = 1) {

        // (1) 検索クエリを先に Store へ通知する。
        // これにより Store 側は「今どの query で検索しているか」を保持できる。
        dispatcher.dispatch(.searchQuery(query))

        // (2) ローディング開始。
        // UI 側は isRepositoriesFetching を見てスピナー表示などを行える。
        dispatcher.dispatch(.isRepositoriesFetching(true))

        // (3) API 通信開始。
        //
        // searchRepositories(...) は Observable を返す想定であり、
        // その Observable から repositories と pagination のペアを受け取る。
        //
        // take(1) の意味:
        // - 最初の onNext を1回だけ受け取って完了する
        // - 多重イベントや無限ストリームにならない前提を明示している
        //
        // ここでは戻り値 Disposable を `_ =` で捨てている。
        // 通信途中でキャンセルしたい要件があるなら DisposeBag 管理や明示破棄が必要になる。
        _ = apiSession.searchRepositories(query: query, page: page)
            .take(1)

            // (4) 通信結果を購読する。
            .subscribe(

                // 成功時:
                // repositories と pagination を受け取り、それぞれ Action に変換して dispatch する。
                onNext: { [dispatcher] repositories, pagination in

                    // 検索結果一覧を Store に反映。
                    dispatcher.dispatch(.searchRepositories(repositories))

                    // ページネーション情報を Store に反映。
                    dispatcher.dispatch(.searchPagination(pagination))

                    // ローディング終了。
                    dispatcher.dispatch(.isRepositoriesFetching(false))
                },

                // 失敗時:
                // エラーを Store に流し、その後ローディング終了を通知する。
                onError: { [dispatcher] error in
                    dispatcher.dispatch(.error(error))
                    dispatcher.dispatch(.isRepositoriesFetching(false))
                }
            )
    }

    /// 検索フィールド編集中フラグを更新する。
    ///
    /// これは API 通信を伴わない単純な UI 状態更新 Action である。
    /// Store 側では isSearchFieldEditing を更新し、
    /// View 側は候補表示・キャンセルボタン表示などを切り替えられる。
    func setIsSearchFieldEditing(_ isEditing: Bool) {
        dispatcher.dispatch(.isSearchFieldEditing(isEditing))
    }

    /// 現在の検索結果をクリアする。
    ///
    /// 新しい検索を始める前や、検索画面をリセットするときに利用できる。
    /// Store 側では repositories を空配列にする想定。
    func clearRepositories() {
        dispatcher.dispatch(.clearSearchRepositories)
    }
}

// MARK: - Favorite
//
// お気に入り機能に関する Action 発行群。
// ここでは API 通信ではなく、ローカルキャッシュへの保存・読み込みが副作用となる。
extension ActionCreator {

    /// リポジトリをお気に入りに追加する。
    ///
    /// アルゴリズム:
    /// 1. 現在の favorites を localCache から取得
    /// 2. 新しい repository を末尾に追加
    /// 3. localCache に保存
    /// 4. 更新済み favorites 配列を Action として dispatch
    ///
    /// 注意:
    /// - 現状は重複追加を防いでいない
    /// - 同じ repository を複数回 add すると重複する可能性がある
    /// - 実務では id ベースで unique 化することが多い
    func addFavoriteRepository(_ repository: GitHub.Repository) {
        let repositories = localCache[.favorites] + [repository]
        localCache[.favorites] = repositories
        dispatcher.dispatch(.setFavoriteRepositories(repositories))
    }

    /// リポジトリをお気に入りから削除する。
    ///
    /// アルゴリズム:
    /// 1. 現在の favorites を取得
    /// 2. repository.id が一致するものを除外する
    /// 3. localCache に保存
    /// 4. 更新済み favorites を dispatch
    ///
    /// id ベースで比較しているため、同一インスタンスでなくても同じ Repo として削除できる。
    func removeFavoriteRepository(_ repository: GitHub.Repository) {
        let repositories = localCache[.favorites].filter { $0.id != repository.id }
        localCache[.favorites] = repositories
        dispatcher.dispatch(.setFavoriteRepositories(repositories))
    }

    /// 保存済みのお気に入り一覧を読み込んで Store に反映する。
    ///
    /// アルゴリズム:
    /// 1. localCache から favorites を取得
    /// 2. それを Action として dispatch
    ///
    /// 主に画面起動時やアプリ起動時の初期ロードで使う。
    func loadFavoriteRepositories() {
        dispatcher.dispatch(.setFavoriteRepositories(localCache[.favorites]))
    }
}

// MARK: - Others
//
// 検索やお気に入り以外の補助的 Action 群。
extension ActionCreator {

    /// 現在選択されているリポジトリを更新する。
    ///
    /// これにより Store 側が「今どの Repo が選択されているか」を保持できる。
    /// 詳細画面遷移や選択ハイライトなどの UI で利用できる。
    func setSelectedRepository(_ repository: GitHub.Repository?) {
        dispatcher.dispatch(.selectedRepository(repository))
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1. 検索リクエストのキャンセル管理
//    現状は Disposable を捨てているため、画面離脱や連続検索時のキャンセル制御ができない。
//    DisposeBag 管理や latest 検索のみ有効にする仕組みがあると実用的。
//
// 2. ローディング終了の共通化
//    成功時と失敗時の両方で isRepositoriesFetching(false) を dispatch している。
//    do(onDispose:) などで共通化できる場合がある。
//
// 3. お気に入り追加時の重複防止
//    addFavoriteRepository では単純に append しているため重複可能。
//    id ベースの unique 化を入れると Store 側が扱いやすい。
//
// 4. Action の順序保証
//    Flux では Action の順序が UI 挙動に直結する。
//    例えば clearRepositories() を検索開始前に呼ぶかどうかで一覧表示の挙動が変わる。
//    ActionCreator 側で “どの順番で何を流すか” を明確にするのが重要。
//```