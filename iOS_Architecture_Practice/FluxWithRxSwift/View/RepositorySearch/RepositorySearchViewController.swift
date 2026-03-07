//
//  RepositorySearchViewController.swift
//  FluxWithRxSwift
//
//  この ViewController は GitHub Repository を検索する画面を実装している。
//  アーキテクチャは Flux + RxSwift を採用しており、ViewController の役割は
//
//      「UIイベントを ActionCreator に伝える」
//      「Store の状態変化を購読して UI を更新する」
//
//  の2つに限定されている。
//
//  つまり、この ViewController 自体は
//
//      ・API通信
//      ・状態管理
//
//  を一切行わない。
//
//  それらは
//
//      ActionCreator
//      Store
//
//  に委譲される。
//
//  Flux の全体フローの中では次の位置にある。
//
// -------------------------------------------------------------
//                 User Event
//                      │
//                      ▼
//         RepositorySearchViewController
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
//             SearchRepositoryStore
//                      │
//                      ▼
//           repositoriesObservable
//                      │
//                      ▼
//         RepositorySearchViewController
//              (UI 更新)
// -------------------------------------------------------------
//

import GitHub
import RxCocoa
import RxSwift
import UIKit

final class RepositorySearchViewController: UIViewController {

    // MARK: - UI Components

    /// Repository 検索結果を表示する TableView。
    ///
    /// 検索結果は SearchRepositoryStore が保持しており、
    /// repositoriesObservable の変更をトリガに reloadData する。
    @IBOutlet private(set) weak var tableView: UITableView!

    /// Repository 検索用の UISearchBar。
    ///
    /// RxSwift を利用してユーザ入力イベントを購読し、
    /// ActionCreator にイベントを伝える。
    @IBOutlet private(set) weak var searchBar: UISearchBar!

    // MARK: - Flux Dependencies

    /// Action を生成するオブジェクト。
    ///
    /// ViewController は副作用（API通信など）を持たないため、
    /// ユーザ操作はすべて ActionCreator に委譲する。
    private let actionCreator: ActionCreator

    /// Repository 検索状態を保持する Store。
    ///
    /// 検索結果
    /// ページネーション
    /// loading状態
    /// 検索入力状態
    ///
    /// などがここに集約される。
    private let searchStore: SearchRepositoryStore

    /// 現在選択されている Repository を保持する Store。
    ///
    /// この ViewController では直接使っていないが、
    /// DataSource や別画面遷移で利用される可能性がある。
    private let selectedStore: SelectedRepositoryStore

    // MARK: - TableView DataSource

    /// TableView の DataSource。
    ///
    /// RepositorySearchDataSource は
    ///
    /// ・セル表示
    /// ・ページネーション
    /// ・セルタップ
    ///
    /// などを担当する。
    private let dataSource: RepositorySearchDataSource

    /// RxSwift の購読ライフサイクル管理。
    ///
    /// ViewController が解放されると同時に
    /// すべての購読が dispose される。
    private let disposeBag = DisposeBag()

    // MARK: - Initializer

    /// Dependency Injection による初期化。
    ///
    /// デフォルトでは shared Store を使うが、
    /// テスト時にはモック Store を注入できる設計になっている。
    init(actionCreator: ActionCreator = .init(),
         searchRepositoryStore: SearchRepositoryStore = .shared,
         selectedRepositoryStore: SelectedRepositoryStore = .shared) {

        self.searchStore = searchRepositoryStore
        self.actionCreator = actionCreator
        self.selectedStore = selectedRepositoryStore

        /// DataSource にも同じ Store と ActionCreator を渡す。
        self.dataSource = RepositorySearchDataSource(
            actionCreator: actionCreator,
            searchRepositoryStore: searchRepositoryStore
        )

        super.init(nibName: "RepositorySearchViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    /// ViewController がロードされたときに呼ばれる。
    ///
    /// ここでは
    ///
    /// ・UI初期化
    /// ・Store購読
    /// ・ユーザイベント購読
    ///
    /// を設定する。
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Search Repositories"

        /// DataSource に TableView を設定する。
        dataSource.configure(tableView)

        // MARK: - Store → UI バインド

        /// repositoriesObservable を購読し、
        /// Repository一覧が更新されたら TableView を reload する。
        ///
        /// map { _ in } を使っている理由:
        /// repositories の内容自体は使わず、
        /// 「変更された」というイベントだけ欲しいため。
        searchStore.repositoriesObservable
            .map { _ in }
            .bind(to: Binder(tableView) { tableView, _ in
                tableView.reloadData()
            })
            .disposed(by: disposeBag)

        /// 検索フィールド編集中かどうかを監視する。
        ///
        /// 編集中の場合
        /// ・背景黒
        /// ・TableView 無効化
        /// ・Cancelボタン表示
        ///
        /// 編集終了時
        /// ・背景白
        /// ・TableView有効
        /// ・Cancelボタン非表示
        searchStore.isSearchFieldEditingObservable
            .bind(to: Binder(self) { me, isFieldEditing in
                UIView.animate(withDuration: 0.3) {

                    if isFieldEditing {

                        me.view.backgroundColor = .black
                        me.tableView.isUserInteractionEnabled = false
                        me.tableView.alpha = 0.5
                        me.searchBar.setShowsCancelButton(true, animated: true)

                    } else {

                        me.searchBar.resignFirstResponder()
                        me.view.backgroundColor = .white
                        me.tableView.isUserInteractionEnabled = true
                        me.tableView.alpha = 1
                        me.searchBar.setShowsCancelButton(false, animated: true)
                    }
                }
            })
            .disposed(by: disposeBag)

        // MARK: - SearchBar イベント

        /// Cancel ボタンが押されたとき。
        ///
        /// 検索編集状態を false に戻す。
        searchBar.rx.cancelButtonClicked
            .subscribe(onNext: { [actionCreator] in
                actionCreator.setIsSearchFieldEditing(false)
            })
            .disposed(by: disposeBag)

        /// SearchBar が編集開始されたとき。
        ///
        /// Store に editing 状態を通知する。
        searchBar.rx.textDidBeginEditing
            .subscribe(onNext: { [actionCreator] in
                actionCreator.setIsSearchFieldEditing(true)
            })
            .disposed(by: disposeBag)

        /// Search ボタンが押されたとき。
        ///
        /// アルゴリズム:
        ///
        /// 1. 検索文字列取得
        /// 2. 検索結果クリア
        /// 3. Repository検索
        /// 4. 編集状態終了
        searchBar.rx.searchButtonClicked
            .withLatestFrom(searchBar.rx.text)
            .subscribe(onNext: { [actionCreator] text in

                if let text = text, !text.isEmpty {

                    /// 既存検索結果をクリア
                    actionCreator.clearRepositories()

                    /// API検索開始
                    actionCreator.searchRepositories(query: text)

                    /// 編集終了
                    actionCreator.setIsSearchFieldEditing(false)
                }
            })
            .disposed(by: disposeBag)
    }
}