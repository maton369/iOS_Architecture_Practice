//
//  ViewController.swift
//  OriginalMVCSample
//
//  このサンプルは「原初の MVC（Smalltalk 由来の MVC の捉え方）」に寄せた構造になっている。
//  重要ポイントは次の通り。
//  - UIKit の UIViewController は、必ずしも “MVC の Controller” ではない（ここでは単なるホスト/ライフサイクルの器）
//  - 本当の意味での Controller は View の中で生成され、UIイベントを Model に伝える役に徹する
//  - View は Model の変更を購読（通知）して、見た目（UILabel）を更新する
//
//  つまり、UIKit で一般的な「ViewController が View と Model を全部触る」MVC ではなく、
//  「View と Controller と Model が（概念上）三角形で連携する」古典 MVC をコードに落とした例である。
//  （ただし UIKit は小さな部品としての Controller を View が持つ文化が薄いので、実用では工夫が必要になりがち）
//

import UIKit

/// 原初 MVC の場合、`ViewController` はあくまで UIKit の仕組みに則って存在するだけであって、
/// 実際の Controller としての仕事には関与しないことにご注意ください。
///
/// - ここでの ViewController の責務:
///   - UIKit のライフサイクルに従って View を生成し、画面に載せる
///   - 「外部から View に Model を渡す」入口になる（DI: Dependency Injection の最小形）
///
/// - 逆に “しないこと”:
///   - ボタンタップの処理（それは Controller がやる）
///   - Model の状態監視（それは View がやる）
///
/// この分離により、UIKit 都合（画面遷移、loadView、viewDidLoad 等）を
/// アーキテクチャの本質（Controller/Model/View）から切り離して考えられる。
class ViewController: UIViewController {

	/// lazy にしているのは「初回アクセスで生成」したいだけ。
	/// loadView のタイミングで確実に生成されるので、必須ではないがサンプルとして分かりやすい。
	private lazy var myView = View()

	override func loadView() {
		/// UIKit では view プロパティに root view をセットするのが基本。
		/// Storyboard/XIB を使わない場合はここで自前 View を割り当てる。
		view = myView
		view.backgroundColor = .white
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		/// ここで外部から View に Model を渡しているとイメージしてください。
		///
		/// 重要: ViewController が Model を保持していない点がこのサンプルの肝。
		/// - ViewController は「渡す」だけ
		/// - 以後の UI イベント処理や状態更新は View/Controller/Model の三者で完結する
		///
		/// DI の観点では、Composition Root（依存を組み立てる場所）がここにある。
		myView.myModel = Model()
	}
}

/// Model は「アプリの状態」と「その状態を変える操作（ドメイン操作）」を持つ。
///
/// - count を内部状態として保持
/// - countUp / countDown で状態を更新
/// - 状態が変わったら通知を飛ばす（Observer パターン）
///
/// 本来、Model は「通知機構に依存しない」方がテストもしやすいが、
/// サンプルでは “変更通知” を明示的に見せるため NotificationCenter を利用している。
class Model {

	/// この Model 専用の NotificationCenter を持っている点が特徴。
	///
	/// - もし NotificationCenter.default を使うと、
///   グローバル空間にイベントが拡散し、イベント名衝突や関係ない購読の混入が起きやすい。
	/// - 専用インスタンスなら、観測範囲が「この Model の利用者」に閉じるため、
///   依存関係の局所性が保ちやすい。
	///
	/// ただし実用では「Publisher/Callback/Delegate」など別手段が使われることも多い。
	let notificationCenter = NotificationCenter()

	/// count は外部から “読み取りのみ” 可能にしている。
	/// - private(set) により、外部が勝手に count を書き換えられない
	/// - 状態変更は必ず countUp / countDown を経由する
	/// これにより Model の不変条件（ルール）を守りやすくなる。
	private(set) var count = 0 {
		didSet {
			/// count が変化したら通知を投稿する。
			///
			/// - name: "count" というイベント名（文字列）は実用だと定数化したい（typo 防止）
			/// - userInfo: ["count": count] で値を運ぶ
			///
			/// 注意:
			/// - didSet は “値が変わるたび” に呼ばれるため、頻繁更新だと通知が多発する。
			/// - UI 更新はメインスレッドで行うべきだが、ここでは queue: nil なので
			///   通知を受ける側の実行スレッドが投稿側に依存する（＝将来のバグ源）。
			notificationCenter.post(
				name: .init(rawValue: "count"),
				object: nil,
				userInfo: ["count": count]
			)
		}
	}

	/// Model の操作（ユースケース）: カウントを 1 減らす
	/// ここに「0 未満にしない」等のルールがあるなら、この層で守るのが自然。
	func countDown() {
		count -= 1
	}

	/// Model の操作（ユースケース）: カウントを 1 増やす
	func countUp() {
		count += 1
	}
}

/// ここでの Controller は「UI イベントを Model の操作に変換する」役だけを持つ。
///
/// - View の button tap を受けて
/// - Model の countUp / countDown を呼ぶ
///
/// つまり “入力（イベント）→ ドメイン操作” の変換器である。
///
/// UIKit の UIViewController と違い、表示更新は行わない（View が担当）。
class Controller {

	/// Model は弱参照になっている。
	///
	/// これは「循環参照を避ける」意図が見えるが、実際には:
	/// - Controller は View に保持されている（myController）
	/// - Model は ViewController が生成し View が強参照（myModel）で持つ
	/// - Model が Controller を保持しているわけではない
	///
	/// なので循環参照は起きにくく、weak は “なくても動く” 可能性が高い。
	/// ただし、設計として「Controller は Model の所有者ではない」を明示したいなら weak はあり。
	///
	/// 注意:
	/// - weak にすると Model が解放された瞬間に nil になり、イベントが無視される。
	///   ライフサイクル設計が曖昧なままだとデバッグが難しくなる場合もある。
	weak var myModel: Model?

	/// View が Controller.Type を受け取って init する都合で required init。
	/// 依存注入（DI）をするなら、init(model:) にしたいところだが、ここでは後で代入している。
	required init() { }

	/// -1 ボタンが押されたら Model の countDown を呼ぶ
	/// @objc は Selector 経由で呼ぶために必要（UIButton addTarget/action）
	@objc func onMinusTapped() {
		myModel?.countDown()
	}

	/// +1 ボタンが押されたら Model の countUp を呼ぶ
	@objc func onPlusTapped() {
		myModel?.countUp()
	}
}

/// View は「見た目（UI）」と「Model の状態反映（表示更新）」を担当する。
///
/// ここが原初 MVC っぽさの強い部分で、View が Model を監視して自分を更新する。
///
/// さらにこのサンプルでは:
/// - View が Controller を生成し、ボタンイベントを Controller に委譲する
/// という形で、View が “Controller の組み立ても担う” 作りになっている。
///
/// 実用では Controller の生成は外部（Composition Root）に出すことも多いが、
/// 「View が Controller を持つ」関係を見せたい意図だと思われる。
class View: UIView {

	// MARK: - UI Components

	/// 表示だけ担当するラベル（Model.count を表示）
	let label = UILabel()

	/// -1 ボタン（イベントは Controller に流す）
	let minusButton = UIButton()

	/// +1 ボタン（イベントは Controller に流す）
	let plusButton = UIButton()

	// MARK: - MVC Wiring

	/// この View が生成する Controller の型を差し替えられるようにしている。
	///
	/// - テスト用 Controller に差し替える
	/// - 別実装（例えばログ付き、別の操作）に差し替える
	/// といった拡張点になる。
	///
	/// ただし「View が Controller を生成する」設計だと DI の自由度が下がりがちなので、
	/// 実用では外から Controller インスタンスそのものを注入する設計も検討される。
	var defaultControllerClass: Controller.Type = Controller.self

	/// View が保持する Controller インスタンス。
	/// - ボタンのターゲットとして登録されるので、少なくとも View の生存中は生きていてほしい
	/// - もしローカル変数だけだと解放されて addTarget が無効化される可能性があるため保持している
	private var myController: Controller?

	/// View が観測する Model。
	/// ここに Model が注入されることで “画面がデータと結び付く”。
	var myModel: Model? {
		didSet {
			/// Model がセットされたタイミングで:
			/// - Controller の生成
			/// - UI の初期表示
			/// - Model の変更通知の購読
			/// を開始する
			registerModel()
		}
	}

	deinit {
		/// NotificationCenter の removeObserver(self) は、旧 API（addObserver(_:selector:)）だと必須だが、
		/// ここでは addObserver(forName:object:queue:using:) を使っているため、
		/// 本来は「戻り値のトークン（NSObjectProtocol）を保持して removeObserver(token)」が筋。
		///
		/// つまりこの removeObserver(self) は “意図は分かるが、実際には効かない可能性がある”。
		/// 実用化するなら、observerToken をプロパティに持って deinit で外すのが安全。
		myModel?.notificationCenter.removeObserver(self)
	}

	// MARK: - Init

	override init(frame: CGRect) {
		super.init(frame: frame)
		setSubviews()
		setLayout()
	}

	required init?(coder aDecoder: NSCoder) {
		/// Storyboard/XIB を使わない前提なので nil を返している。
		/// ただし実務では fatalError("init(coder:) has not been implemented") の方が意図が明確。
		return nil
	}

	// MARK: - UI Setup

	private func setSubviews() {

		addSubview(label)
		addSubview(minusButton)
		addSubview(plusButton)

		label.textAlignment = .center

		/// サンプルなので色分けで役割が分かりやすいようにしている。
		label.backgroundColor = .blue
		minusButton.backgroundColor = .red
		plusButton.backgroundColor = .green

		minusButton.setTitle("-1", for: .normal)
		plusButton.setTitle("+1", for: .normal)
	}

	private func setLayout() {

		/// AutoLayout をコードで書く際は translatesAutoresizingMaskIntoConstraints を false
		label.translatesAutoresizingMaskIntoConstraints = false
		plusButton.translatesAutoresizingMaskIntoConstraints = false
		minusButton.translatesAutoresizingMaskIntoConstraints = false

		/// レイアウトは:
		/// 上: label
		/// 下: [-1][+1] ボタンが横並び
		/// という構造。
		label.topAnchor.constraint(equalTo: topAnchor).isActive = true
		label.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
		label.rightAnchor.constraint(equalTo: rightAnchor).isActive = true

		/// label の下端は 2 つのボタンの上端に揃える
		label.bottomAnchor.constraint(equalTo: minusButton.topAnchor).isActive = true
		label.bottomAnchor.constraint(equalTo: plusButton.topAnchor).isActive = true

		/// label の高さをボタンの高さと同じにする（上:label 下:buttons の 2 段均等）
		label.heightAnchor.constraint(equalTo: minusButton.heightAnchor).isActive = true
		label.heightAnchor.constraint(equalTo: plusButton.heightAnchor).isActive = true

		minusButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
		plusButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

		minusButton.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
		minusButton.rightAnchor.constraint(equalTo: plusButton.leftAnchor).isActive = true
		plusButton.rightAnchor.constraint(equalTo: rightAnchor).isActive = true

		/// 2 ボタンの幅を等しくして左右均等割り
		minusButton.widthAnchor.constraint(equalTo: plusButton.widthAnchor).isActive = true
	}

	// MARK: - Model Registration (MVC Wiring)

	private func registerModel() {

		guard let model = myModel else { return }

		// --- Controller の生成と接続 ---

		/// View 自身が Controller を生成する。
		/// この時点で「View は Controller を所有する」形になる。
		let controller = defaultControllerClass.init()

		/// Controller に Model を渡す（イベント → ドメイン操作に必要）
		controller.myModel = model

		/// View が Controller を保持しておく（ターゲットとして使うため & ライフサイクル維持）
		myController = controller

		// --- UI の初期表示 ---

		/// Model の現在値を UI に反映
		label.text = model.count.description

		// --- UI イベントを Controller に配線 ---

		/// ボタンタップは View が受けず、Controller に委譲する（入力変換器としての役割）
		///
		/// 注意:
		/// addTarget は target を強参照しない仕様なので、controller を保持しておく必要がある。
		minusButton.addTarget(controller, action: #selector(Controller.onMinusTapped), for: .touchUpInside)
		plusButton.addTarget(controller, action: #selector(Controller.onPlusTapped), for: .touchUpInside)

		// --- Model 変更通知を購読して UI を更新 ---

		/// Model の count 変更を購読し、label を更新する。
		/// ここが「View が Model を監視して自分を更新する」という原初 MVC の要。
		///
		/// 注意点（実務での落とし穴）:
		/// - queue: nil の場合、通知を受けるスレッドは投稿側に依存する。
		///   UI 更新は main thread が必須なので、queue: .main を指定するか DispatchQueue.main.async が必要。
		/// - addObserver(forName:using:) の戻り値トークンを保持して removeObserver(token) すべき。
		/// - [unowned self] は self が先に解放される可能性があるとクラッシュする。
		///   安全側なら [weak self] で guard let self = self else { return } がよく使われる。
		model.notificationCenter.addObserver(
			forName: .init(rawValue: "count"),
			object: nil,
			queue: nil,
			using: { [unowned self] notification in
				if let count = notification.userInfo?["count"] as? Int {
					self.label.text = count.description
				}
			}
		)
	}
}