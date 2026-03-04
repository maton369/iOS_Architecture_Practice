//
//  Coordinator.swift
//
//  このファイル（もしくはこの宣言）は iOS アプリでよく使われる “Coordinator パターン” の最小要素である。
//  Coordinator パターンは、主に「画面遷移（Navigation）」と「画面生成（DI/組み立て）」の責務を
//  ViewController から分離するためのアーキテクチャ上のテクニックである。
//
//  なぜ Coordinator が必要になるか（背景）:
//  - ViewController が
//      - 画面表示（View）
//      - ユーザ操作の処理（Controller）
//      - 画面遷移（push/present）
//      - 次画面の依存注入（Presenter/UseCase/Repository の生成）
//    などを全部抱えると “Massive View Controller” になりやすい。
//  - 画面遷移はアプリ全体の構造に関わるため、VCに散らばると追跡が難しく、テストもしづらい。
//  - Coordinator に遷移を集約すると、
//      - 遷移フローの見通しが良くなる
//      - VC は “表示と入力受付” に専念できる
//      - DI（依存注入）を Coordinator に集約できる
//    といった利点が得られる。
//
//  Coordinator の基本思想（アルゴリズム）:
//
//      1) Coordinator が最初の画面（Root）を作る
//      2) その画面に必要な依存（Presenter/UseCase 等）を注入する
//      3) NavigationController に set/push/present して表示を開始する
//      4) 画面内イベント（ボタンタップ等）をトリガに Coordinator が次の遷移を行う
//
//  つまり “画面フローの開始点” と “画面間のつなぎ” を Coordinator が握る。
//

// MARK: - Coordinator Protocol
//
// Coordinator が最低限持つべき振る舞いを定義するプロトコル。
// 具体的な Coordinator（AppCoordinator, AuthCoordinator, SearchCoordinator など）は
// この protocol に準拠し、start() の中で “フロー開始時の画面構築・表示” を行う。
protocol Coordinator {

    // MARK: - start()
    //
    // Coordinator が管理するフロー（画面遷移のまとまり）を開始するメソッド。
    //
    // 典型的な start() の中身（概念）:
    //
    //   - 初期画面の ViewController を生成
    //   - 依存注入（Presenter / ViewModel / UseCase / Repository 等）
    //   - Root として navigationController に setViewControllers する、または present する
    //
    // アルゴリズムとしては “フロー開始の初期化処理” に相当する。
    //
    // 例（概念図）:
    //
    //   func start() {
    //       let vc = SearchViewController()
    //       let presenter = SearchPresenter(...)
    //       vc.inject(presenter)
    //       navigationController.setViewControllers([vc], animated: false)
    //   }
    //
    // start() を呼ぶ側は通常 AppDelegate / SceneDelegate / 親Coordinator などであり、
    // アプリ起動や特定フロー開始時に呼ばれる。
    func start()
}

//
// MARK: - 実務でよく追加される拡張（参考）
//
// 1) 子Coordinator管理（フロー分割）
//    - var childCoordinators: [Coordinator] { get set }
//    - フロー終了時に子を解放してメモリリークを防ぐ
//
// 2) 遷移先の通知（Delegate/Closure）
//    - ログイン完了 → AuthCoordinator が AppCoordinator に通知してメインフローへ
//
// 3) 依存注入の集約
//    - UseCase や Gateway の生成を Coordinator に寄せ、VC は “注入される側” に徹する
//
// ただし、この宣言は “最小形” として start() だけに絞っているため、学習用として分かりやすい。
//```