//
//  Transitioner.swift
//
//  目的:
//  UIViewController の遷移（push / pop / present / dismiss）を
//  「呼び出し側の型（CoordinatorやRouter）から見て統一された API」として扱うための抽象である。
//
//  よくある問題:
//  - 画面遷移は navigationController の有無に依存する（push/popは UINavigationController が必要）
//  - present/dismiss は “今の VC が表示しているかどうか” に依存する
//  - 画面遷移の呼び出しが ViewController に散らばると、アーキテクチャ（Coordinator等）の境界が崩れる
//
//  この Transitioner は、UIViewController に対して
//  「遷移操作を行える最小インターフェイス」を与えることで、
//  遷移を呼び出す側（例: Coordinator/Router）が
//  “具体的な UIKit API” を直接触る部分を局所化する狙いがある。
//
//  また `where Self: UIViewController` により、
//  Transitioner を採用できるのは UIViewController サブクラスに限定される。
//  これにより、extension 内で navigationController / present / dismiss など
//  UIViewController のAPIを安全に使える。
//

import UIKit

// MARK: - Transitioner
//
// 遷移操作を抽象化する Protocol。
// Self を UIViewController に縛っているため、
/// この protocol を採用するクラスは “画面そのもの” として振る舞える（＝ UIKit の遷移APIを持つ）。
//
// 注意:
// ここで列挙しているメソッド群は
// - UINavigationController を使う遷移（push/pop）
// - modal を使う遷移（present/dismiss）
// をまとめた “遷移の統一インターフェイス” である。
//
// ただし実務では、push/pop と present/dismiss は前提条件が異なるため、
// - NavigationTransitioner
// - ModalTransitioner
// に分ける設計もよくある。
// このコードは “単一の遷移窓口” を作る方向性になっている。
protocol Transitioner where Self: UIViewController {

    // MARK: - Navigation stack based transitions

    /// navigationController に push する。
    /// 前提: Self が UINavigationController のスタック内にいること。
    func pushViewController(_ viewController: UIViewController, animated: Bool)

    /// navigationController から pop する。
    /// 前提: Self が UINavigationController のスタック内にいること。
    func popViewController(animated: Bool)

    /// navigationController の root まで pop する。
    func popToRootViewController(animated: Bool)

    /// 指定した viewController まで pop する。
    /// 前提: 指定 viewController が navigation stack 内に存在すること。
    func popToViewController(_ viewController: UIViewController, animated: Bool)

    // MARK: - Modal based transitions

    /// modal で viewController を present する。
    /// completion は present 完了後に呼ばれる。
    func present(
        viewController: UIViewController,
        animated: Bool,
        completion: (() -> ())?
    )

    /// modal を dismiss する。
    func dismiss(animated: Bool)
}

// MARK: - Default Implementations
//
// protocol extension によりデフォルト実装を提供している。
// Transitioner を採用した UIViewController は、
// 実装を書かずにこれらの遷移操作を使えるようになる。
extension Transitioner {

    // MARK: - push

    /// UINavigationController を使って push するデフォルト実装。
    ///
    /// アルゴリズム:
    /// 1) navigationController を取得
    /// 2) nil なら遷移できないので return（現実装）
    /// 3) pushViewController を呼ぶ
    ///
    /// NOTE:
    /// - 現状は navigationController が nil の場合に “何も起きない”。
    ///   これは不具合に気づきにくい挙動になりやすい。
    /// - FIXME コメントにある通り、実務では
    ///     preconditionFailure / fatalError
    ///   で落として “設計上あり得ない状態” を早期検知する方針もある。
    /// - ただし、画面が常に nav stack にいるとは限らないアプリでは、
    ///   ここでクラッシュさせるのは危険な場合もあるため、
    ///   アプリの方針に合わせて選ぶのがよい。
    func pushViewController(_ viewController: UIViewController,
                            animated: Bool) {
        guard let nc = navigationController else { return }
        // FIXME:
        //   ここは guard で握りつぶすと “遷移しない” バグが静かに発生し得る。
        //   「設計上 nav が必須」なら preconditionFailure で落とす方が気づきやすい。
        //   例: preconditionFailure("Transitioner requires navigationController")
        nc.pushViewController(viewController, animated: animated)
    }

    // MARK: - pop

    /// navigation stack の先頭（現在画面）を pop する。
    ///
    /// 実装方針は push と同じで、
    /// 1) navigationController を取得
    /// 2) nil なら return（またはクラッシュ）
    /// 3) popViewController を呼ぶ
    ///
    /// 現在は未実装なので、Coordinator/Router 側が pop を使った瞬間に
    /// “何も起きない” というバグになる。
    /// 実運用ではここも push 同様に実装するべきである。
    func popViewController(animated: Bool) {
        guard let nc = navigationController else { return }
        nc.popViewController(animated: animated)
    }

    // MARK: - popToRoot

    /// rootViewController まで pop する。
    /// 設計上 “ホームに戻る” 的な遷移が必要なときに使う。
    func popToRootViewController(animated: Bool) {
        guard let nc = navigationController else { return }
        nc.popToRootViewController(animated: animated)
    }

    // MARK: - popToViewController

    /// 指定 VC まで pop する。
    /// 指定 VC がスタック内に存在しない場合は pop できないので、
    /// 実務では存在確認のログなどを入れることもある。
    func popToViewController(_ viewController: UIViewController, animated: Bool) {
        guard let nc = navigationController else { return }
        nc.popToViewController(viewController, animated: animated)
    }

    // MARK: - present

    /// modal present のデフォルト実装。
    ///
    /// 注意点:
    /// このコードは現状 “無限再帰” になっている。
    ///
    /// func present(viewController:..., animated:..., completion:...) {
    ///     present(viewController, animated:..., completion:...)
    /// }
    ///
    /// と書いてしまうと、同じシグネチャが選ばれて自分自身を呼び続ける。
    ///
    /// 正しくは UIViewController の present(_:animated:completion:) を呼びたいので、
    /// 引数ラベルと型を合わせて呼ぶ必要がある。
    /// 例:
    ///   self.present(viewController, animated: animated, completion: completion)
    ///
    /// self を付けても同名メソッドがある場合は解決されないことがあるので、
    /// 下のように “UIViewController のメソッド” を意図して呼ぶ形にするのが安全。
    ///
    ///   (self as UIViewController).present(viewController, animated: animated, completion: completion)
    ///
    /// ただし、ここでは where Self: UIViewController なので self は UIViewController である。
    /// Swift のオーバーロード解決を意識して明示するのがポイント。
    func present(viewController: UIViewController,
                 animated: Bool,
                 completion: (() -> ())? = nil) {

        // ✅ UIViewController の present を呼ぶ
        (self as UIViewController).present(viewController, animated: animated, completion: completion)
    }

    // MARK: - dismiss

    /// modal を dismiss するデフォルト実装。
    /// present と同様に、UIViewController の dismiss を呼ぶ必要がある。
    func dismiss(animated: Bool) {

        // ✅ UIViewController の dismiss を呼ぶ
        (self as UIViewController).dismiss(animated: animated, completion: nil)
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) “握りつぶし” か “クラッシュ” かの方針を統一する
//    - navigationController が nil の時に return すると、バグが静かに潜む。
//    - ただし、起動直後など nav が未構築のタイミングがあり得るならクラッシュは危険。
//    - preconditionFailure + ログ など、環境（Debug/Release）で挙動を変える設計もある。
//
// 2) 遷移APIを用途ごとに分割する
//    - NavigationTransitioner（push/pop）
//    - ModalTransitioner（present/dismiss）
//    と分けると、呼び出し側が “今できる遷移” を型で表現できる。
//
// 3) 未実装メソッドの放置を避ける
//    - pop 系が空実装だと “呼んでも何も起きない” バグになる。
//    - 本当に使わないなら fatalError("not supported") の方が気づきやすい。
//
// 4) push/present の呼び出しスレッド
//    - UIKit 遷移はメインスレッドで行うべきなので、
//      呼び出し側で DispatchQueue.main.async を徹底するか、
//      Transitioner 側で保証するか方針を決めると良い。
//```