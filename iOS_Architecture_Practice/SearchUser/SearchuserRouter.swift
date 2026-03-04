//
//  SearchUserRouter.swift
//
//  このファイルは（MVP / VIPER 系でよく出てくる）Router の責務を担う。
//  ここでの Router は「画面遷移の意思決定」と「遷移先画面の組み立て（依存注入）」を担当する。
//
//  目的:
//  - View（ViewController）から画面遷移のロジックを取り除く
//  - 遷移先画面（UserDetail）の生成・依存注入を1箇所に集約する
//  - “どの画面へ遷移するか” を Presenter や View が直接知らない構造にする
//
//  典型的な構造:
//  [View] --(ユーザ操作通知)--> [Presenter] --(遷移要求)--> [Router] --(画面生成 + push)--> [次画面]
//
//  Router がやっている仕事は大きく2つである。
//
//  (1) 画面遷移先の生成（Storyboard から VC を生成）
//  (2) 遷移先に必要な依存（Model / Presenter）を組み立てて注入し、遷移を実行する
//
//  注意:
//  - Router は “遷移を実行するための UI コンテキスト” が必要になる。
//    ここでは view（SearchUserViewProtocol）を保持し、pushViewController を呼んでいる。
//  - view は weak にして循環参照を避けている。
//    Router が view を strong に持つと
//      ViewController → Router → ViewController
//    の循環参照でリークしやすい。
//

import UIKit
import GitHub

// MARK: - SearchUserRouterProtocol
//
// Router が外部に公開するインターフェイス。
// Presenter など “遷移要求を出す側” は、この protocol のみ知っていればよい。
// これにより、Router の実装差し替え（テスト用Router等）がしやすくなる。
//
// ここでは「ユーザ詳細画面へ遷移する」というユースケースのみ公開している。
protocol SearchUserRouterProtocol: class {

    /// 指定した userName を入力として、ユーザ詳細画面へ遷移する。
    /// Router は遷移先の画面生成と依存注入もここで行う。
    func transitionToUserDetail(userName: String)
}

// MARK: - SearchUserRouter
//
// SearchUser 画面の Router 実装。
// - 遷移先の組み立て（UserDetailVC + Model + Presenter）
// - push 遷移の実行
// を1箇所に集約する。
class SearchUserRouter: SearchUserRouterProtocol {

    // MARK: - View (UI context)

    /// 遷移を実行するための “UIコンテキスト”。
    ///
    /// ここでの view は SearchUserViewProtocol（おそらく UIViewController をラップした抽象）であり、
    /// Router は UIKit の navigationController を直接触らずに、
    /// view が持つ pushViewController を通じて遷移を実行する。
    ///
    /// weak にしているのは循環参照を避けるため。
    /// 典型例:
    ///   ViewController(Strong) → Presenter(Strong) → Router(Strong) → ViewController
    /// を防ぐ。
    private(set) weak var view: SearchUserViewProtocol!

    // MARK: - Init

    /// Router は遷移の起点となる view を受け取って初期化する。
    /// view を差し替えられる設計にしておくと、テストでモック view を注入しやすい。
    init(view: SearchUserViewProtocol) {
        self.view = view
    }

    // MARK: - Transition

    /// UserDetail 画面へ遷移する。
    ///
    /// アルゴリズム（この関数がしていること）:
    /// 1) Storyboard から UserDetailViewController を生成する
    /// 2) 遷移先が必要とする Model（UserDetailModel）を生成する
    /// 3) 遷移先の Presenter（UserDetailPresenter）を生成し、必要な依存を注入する
    /// 4) UserDetailViewController に Presenter を inject する（依存注入）
    /// 5) 起点 view から push 遷移を実行する
    ///
    /// ここで重要なのは 1〜4 の “画面組み立て” を Router が持っている点である。
    /// ViewController や Presenter が storyboard / presenter / model を直接触り始めると、
    /// 依存関係が散らばって保守が難しくなる。
    ///
    /// Router に集約すると、
    /// - 遷移先の生成ルール
    /// - 依存注入の手順
    /// - 遷移方式（push/present）
    /// を一括で管理できる。
    func transitionToUserDetail(userName: String) {

        // (1) Storyboard から遷移先 VC を生成
        // storyboard 名 "UserDetail" の initialViewController を取っている。
        // ここが失敗すると as! でクラッシュするため、実務では
        // - guard let にしてログを出す
        // - fatalError で “設定ミス” を即時検知する
        // のように方針を決めて統一するとよい。
        let userDetailVC = UIStoryboard(name: "UserDetail", bundle: nil)
            .instantiateInitialViewController() as! UserDetailViewController

        // (2) 遷移先 Model の生成
        // userName を入力として Model を作る。
        // “画面が必要とする入力を Router が受け取って組み立てる” のが Router の典型。
        let model = UserDetailModel(userName: userName)

        // (3) Presenter の生成（View + Model を束ねる）
        // Presenter は View と Model の間に立って表示ロジックを担当する想定。
        // userName を重複して渡している点は設計次第で整理余地あり。
        // - Model が userName を持っているなら Presenter に渡さない
        // - Presenter が入力を持ち Model を生成する、など方針を揃える
        let presenter = UserDetailPresenter(
            userName: userName,
            view: userDetailVC,
            model: model
        )

        // (4) ViewController へ Presenter を注入
        // “遷移先の依存を組み立てて注入してから表示する” を Router が保証する。
        userDetailVC.inject(presenter: presenter)

        // (5) 遷移の実行
        // ここでは view（遷移元）の pushViewController を通して push している。
        // つまり Router は navigationController を直接扱わず、
        // view の抽象に乗って遷移を実行している（依存方向を整える効果がある）。
        view.pushViewController(userDetailVC, animated: true)
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) storyboard / as! の失敗時の方針を統一する
//    - 設定ミスは早期に落としたいなら fatalError で明示
//    - 本番でのクラッシュ回避を優先するなら guard + ログ + フォールバック
//
// 2) “画面組み立て” を Factory/Builder に寄せる
//    - Router が肥大化しやすいので、UserDetailModuleBuilder を作る設計がよくある。
//      例: let userDetailVC = UserDetailBuilder.build(userName: userName)
//
// 3) 依存注入方式の統一
//    - inject(presenter:) のような後注入は注入漏れが起きる可能性がある。
//    - init(presenter:) のような初期化注入が可能なら安全性が上がる。
//
// 4) “遷移の方法” を統一
//    - push か present かを Router が持っているのは自然だが、画面ごとにブレると追跡が難しい。
//    - アプリ方針（画面遷移規約）を決め、Router 実装に反映すると保守性が上がる。
//```