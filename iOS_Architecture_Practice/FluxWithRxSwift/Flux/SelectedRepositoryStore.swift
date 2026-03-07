//
//  SelectedRepositoryStore.swift
//  FluxWithRxSwift
//
//
//  このファイルは Flux + RxSwift における「現在選択中の Repository」を管理する Store である。
//  Store の役割は一貫しており、Dispatcher から流れてくる Action を受け取り、
//  自分が担当する State だけを更新することである。
//
//  この Store が担当する State は非常に小さい。
//  それは
//
//      「現在選択されている GitHub.Repository が何か」
//
//  という一点だけである。
//
//  例えば、検索結果一覧のセルをタップしたときに
//
//      .selectedRepository(repository)
//
//  という Action が dispatch されると、この Store はその repository を保持する。
//  逆に、検索結果更新・ページネーション・ローディング・お気に入り更新などは
//  この Store の責務ではないため無視する。
//
//  Flux 全体の流れの中で見ると、この Store の位置は次のようになる。
//
// -------------------------------------------------------------
//                 User Event
//                      │
//                      ▼
//                ActionCreator
//                      │
//                 dispatch(Action)
//                      │
//                      ▼
//                  Dispatcher
//                      │
//                      ▼
//            SelectedRepositoryStore
//                      │
//                      ▼
//             repositoryObservable
//                      │
//                      ▼
//                     View
// -------------------------------------------------------------
//
//  つまりこの Store は
//
//      Action(.selectedRepository)
//          ↓
//      BehaviorRelay<Repository?> を更新
//          ↓
//      View が購読して UI を更新
//
//  という最小の一方向データフローを実装している。
//

import GitHub
import RxCocoa
import RxSwift

// MARK: - SelectedRepositoryStore
//
// 「今どの Repository が選択されているか」を保持する Store。
// 検索一覧画面から詳細画面へ遷移するときや、
// 画面内の “選択中状態” を一元管理したいときに使われる想定である。
//
// Store を分割する利点:
// - 検索結果一覧の State と切り離せる
// - お気に入り一覧の State と切り離せる
// - 「選択状態」だけを独立して監視できる
//
// このように Flux では
// 「関心ごとごとに Store を分ける」ことで責務を小さく保つことが多い。
final class SelectedRepositoryStore {

    /// アプリ全体で共有する SelectedRepositoryStore。
    /// singleton 的に使うことで、どこからでも同じ “選択状態” を参照できる。
    static let shared = SelectedRepositoryStore()

    // MARK: - State

    /// 現在選択中の Repository。
    ///
    /// BehaviorRelay を使っている理由:
    /// - 現在値を保持できる
    /// - 新しく購読した相手にも “今選ばれている値” をすぐ流せる
    ///
    /// Optional になっている理由:
    /// - 初期状態では何も選択されていないため nil
    /// - 選択解除を nil で表現できる
    private let _repository = BehaviorRelay<GitHub.Repository?>(value: nil)

    // MARK: - Lifetime

    /// Dispatcher 購読のライフサイクルを管理する DisposeBag。
    /// register(...) が返す Disposable をここに入れることで、
    /// この Store の生存期間中だけ Action を受け取り続ける。
    private let disposeBag = DisposeBag()

    // MARK: - Init

    /// Dispatcher に登録し、selectedRepository に関する Action のみを処理する。
    ///
    /// アルゴリズム:
    ///
    /// 1. dispatcher.register で Action ストリームを購読する
    /// 2. Action が流れてきたら switch で分類する
    /// 3. .selectedRepository(repository) なら State を更新する
    /// 4. それ以外の Action は無視する
    ///
    /// つまりこの Store の reducer 的処理は実質次の1本だけである。
    ///
    ///   .selectedRepository(repository)
    ///       → _repository.accept(repository)
    ///
    /// 非常に単純であるが、責務が明確な良い Store になっている。
    init(dispatcher: Dispatcher = .shared) {
        dispatcher.register(callback: { [weak self] action in

            // Store が解放済みなら何もしない。
            // singleton 運用では長寿命が想定されるが、weak self で安全側に倒している。
            guard let me = self else {
                return
            }

            // この Store が関心を持つ Action だけを処理する。
            switch action {

            case let .selectedRepository(repository):
                // 現在選択中の Repository を更新する。
                //
                // repository は Optional なので、
                // - 実際の Repository が来れば “選択された”
                // - nil が来れば “選択解除された”
                //
                // という意味を持つ。
                me._repository.accept(repository)

            case .searchRepositories,
                 .clearSearchRepositories,
                 .searchPagination,
                 .isRepositoriesFetching,
                 .isSearchFieldEditing,
                 .error,
                 .searchQuery,
                 .setFavoriteRepositories:
                // この Store の責務外の Action は無視する。
                //
                // これは Flux の基本方針であり、
                // 「各 Store は自分の関心のある Action だけを処理する」ことで
                // Store の肥大化を防ぐ。
                return
            }
        })
        .disposed(by: disposeBag)
    }
}

// MARK: - Values
//
// 現在値を同期的に取得するための API。
// UI の一部や遷移時の参照で “今の選択状態” をすぐ見たいときに使える。
extension SelectedRepositoryStore {

    /// 現在選択中の Repository を返す。
    ///
    /// - 選択中なら GitHub.Repository
    /// - 未選択なら nil
    ///
    /// Rx 中心の設計では Observable を購読する方が一貫するが、
    /// 同期的に現在値を見たい場面では value ベースの API も便利である。
    var repository: GitHub.Repository? {
        return _repository.value
    }
}

// MARK: - Observables
//
// 状態変化をリアクティブに購読するための API。
// View や他のレイヤが “選択状態の変化” に反応したいときに利用する。
extension SelectedRepositoryStore {

    /// 選択中 Repository の Observable。
    ///
    /// BehaviorRelay を Observable 化しているため、
    /// - 購読開始時に現在値が流れる
    /// - 以後、選択状態が変わるたびに新しい値が流れる
    ///
    /// 典型的な利用例:
    ///
    ///   store.repositoryObservable
    ///       .observe(on: MainScheduler.instance)
    ///       .subscribe(onNext: { repository in
    ///           // 詳細表示を更新
    ///       })
    ///
    /// Optional なので、nil が流れたときは「未選択」や「解除」を表す。
    var repositoryObservable: Observable<GitHub.Repository?> {
        return _repository.asObservable()
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1. selectedRepository を “ID” だけで持つか、Entity 全体で持つか
//    現状は Repository 全体を保持している。
//    - 利点: 詳細表示やタイトル表示がすぐできる
//    - 欠点: Entity の更新と選択状態の整合性を考える必要がある
//    設計によっては repository.id だけ保持する方が軽量で明確な場合もある。
//
// 2. 選択解除の契約を明文化する
//    nil を “未選択” として使っているため、
//    どの ActionCreator / View が 언제 nil を dispatch するかを決めておくと読みやすい。
//
// 3. reducer ロジックを reduce(action:) に切り出す
//    現状は Action 数が少ないため init 内 switch で十分だが、
//    将来増えるなら reduce(action:) に分離すると可読性が上がる。
//```