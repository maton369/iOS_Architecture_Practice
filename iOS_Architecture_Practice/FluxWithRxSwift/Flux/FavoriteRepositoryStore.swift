//
//  FavoriteRepositoryStore.swift
//  FluxWithRxSwift
//
//
//  このファイルは Flux + RxSwift における「お気に入りリポジトリ専用の Store」を実装している。
//  Store の責務は一貫しており、Dispatcher から流れてくる Action を受け取り、
//  自分が担当する State だけを更新することである。
//
//  この FavoriteRepositoryStore が担当する State は非常に単純で、
//  「お気に入りリポジトリ一覧」そのものだけである。
//
//  Flux の全体像の中では次の位置にある。
//
// -------------------------------------------------------------
//                  User Event
//                       │
//                       ▼
//                 ActionCreator
//                       │
//                  dispatch(Action)
//                       │
//                       ▼
//                   Dispatcher
//                       │
//                       ▼
//           FavoriteRepositoryStore
//                       │
//                       ▼
//              repositoriesObservable
//                       │
//                       ▼
//                      View
// -------------------------------------------------------------
//
//  この Store は SearchRepositoryStore と違って
//  - query
//  - pagination
//  - loading
//  - error
//  といった複数の状態を持たず、
//  「favorites の配列だけを受け取って、そのまま状態に反映する」非常に単純な構造になっている。
//
//  そのため、この Store の本質は
//
//    Action(.setFavoriteRepositories)
//      ↓
//    BehaviorRelay<[Repository]> を更新
//      ↓
//    View が購読して UI を更新
//
//  という一本の流れで理解できる。
//

import GitHub
import RxCocoa
import RxSwift

// MARK: - FavoriteRepositoryStore
//
// FavoriteRepositoryStore は、お気に入り一覧の State を保持する Store である。
// Flux では「Store ごとに責務を小さく分ける」設計がよく採用されるが、
// このクラスもその方針に従っており、favorites 以外の Action は無視する。
final class FavoriteRepositoryStore {

    /// アプリ全体で共有する FavoriteRepositoryStore。
    /// Flux の Store は singleton 的に使われることが多く、
//  UI のどこからでも同じ状態を参照できるようにしている。
    static let shared = FavoriteRepositoryStore()

    // MARK: - State

    /// お気に入りリポジトリ一覧を保持する Relay。
    ///
    /// BehaviorRelay を使う理由:
    /// - 常に「最新値」を保持できる
    /// - 新しく購読を開始した相手にも、現在の favorites 一覧をすぐ流せる
    ///
    /// これは Store の state と非常に相性がよい。
    /// 例えばお気に入り画面を後から開いた場合でも、
    /// 現在のお気に入り一覧がすぐに UI に反映できる。
    private let _repositories = BehaviorRelay<[GitHub.Repository]>(value: [])

    // MARK: - Lifetime

    /// Dispatcher への購読を保持するための DisposeBag。
    ///
    /// dispatcher.register(...) は Disposable を返すため、
    /// これを disposeBag に入れることで、この Store が生きている間だけ購読を維持できる。
    /// Store が解放されれば購読も自動で破棄される。
    private let disposeBag = DisposeBag()

    // MARK: - Init

    /// Dispatcher から Action を購読し、favorites 関連の Action だけを処理する。
    ///
    /// アルゴリズム:
    ///
    /// 1. Dispatcher に register する
    /// 2. Action が流れてきたら switch で分類する
    /// 3. .setFavoriteRepositories のときだけ _repositories を更新する
    /// 4. それ以外は無視する
    ///
    /// つまりこの Store の reducer 的処理は、実質的に
    ///
    ///   .setFavoriteRepositories([Repository])
    ///       → _repositories.accept(repositories)
    ///
    /// の1本だけである。
    ///
    /// そのため責務が非常に明確で、検索系 Action や選択状態 Action を一切持ち込まない点が良い。
    init(dispatcher: Dispatcher = .shared) {

        dispatcher.register(callback: { [weak self] action in

            // Store 自体が解放済みなら何もしない。
            // singleton 運用では通常長生きするが、weak self で保険を掛けている。
            guard let me = self else {
                return
            }

            // この Store が担当する Action だけを処理する。
            switch action {

            case let .setFavoriteRepositories(repositories):
                // favorites 一覧を丸ごと置き換える。
                //
                // SearchRepositoryStore の .searchRepositories が append 戦略だったのに対し、
                // こちらは「お気に入り一覧の全体」をそのまま反映する置換戦略になっている。
                //
                // これは favorites の場合、
                // - localCache から読み込んだ完全な一覧
                // - add/remove 後の更新済み一覧
                // が ActionCreator から毎回まとめて dispatch される設計だからである。
                me._repositories.accept(repositories)

            case .selectedRepository,
                 .searchRepositories,
                 .clearSearchRepositories,
                 .searchPagination,
                 .isRepositoriesFetching,
                 .isSearchFieldEditing,
                 .searchQuery,
                 .error:
                // この Store の責務外の Action は無視する。
                //
                // Flux では「各 Store は関心のある Action だけ処理し、それ以外は黙って通す」
                // という設計が基本である。
                //
                // これにより Store ごとの責務が小さく保たれ、
                // 検索状態と favorites 状態が不必要に混ざらない。
                return
            }
        })
        .disposed(by: disposeBag)
    }
}

// MARK: - Values
//
// 現在値を同期的に参照するための API 群。
// View や DataSource が「今の favorites 一覧」をその場で取りたいときに使う。
extension FavoriteRepositoryStore {

    /// 現在のお気に入りリポジトリ一覧。
    ///
    /// BehaviorRelay の value をそのまま公開している。
    /// 同期参照したいケースでは便利だが、Rx を主軸にするなら Observable 側を購読する設計の方が一貫する。
    var repositories: [GitHub.Repository] {
        return _repositories.value
    }
}

// MARK: - Observables
//
// 状態変化をリアクティブに購読するための API 群。
// UI はこれを subscribe / bind することで、お気に入り一覧の更新に追随できる。
extension FavoriteRepositoryStore {

    /// お気に入りリポジトリ一覧の Observable。
    ///
    /// BehaviorRelay を Observable 化しているため、
    /// - 購読開始時に現在値が流れる
    /// - 以降 favorites が更新されるたびに新しい配列が流れる
    ///
    /// 典型的な使い方:
    ///
    ///   store.repositoriesObservable
    ///       .observe(on: MainScheduler.instance)
    ///       .bind(...)
    ///
    /// UI 更新は通常メインスレッドで行う必要があるため、
    /// View 側で MainScheduler に寄せる設計がよく使われる。
    var repositoriesObservable: Observable<[GitHub.Repository]> {
        return _repositories.asObservable()
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1. Store の reducer ロジックを reduce(action:) に切り出す
//    現状は Action 数が少ないので init 内 switch でも十分だが、
//    今後 Action が増えるなら reduce(action:) として分離した方が読みやすい。
//
// 2. 重複 favorites の扱いをどこで保証するか決める
//    この Store は「渡された配列をそのまま受け入れる」だけなので、
//    重複防止は ActionCreator / LocalCache 側の責務になっている。
//    責務分離としては正しいが、設計上どこで unique を保証するかは明文化した方がよい。
//
// 3. Observable 公開だけに寄せるか、Value API も残すかを統一する
//    Rx 中心の設計では value アクセスを減らし、購読ベースに寄せた方が一貫性が出ることが多い。
//```