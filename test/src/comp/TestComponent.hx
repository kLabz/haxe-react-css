package comp;

@:css
@:css.priority(10)
class TestComponent extends ReactComponent {
	static var styles:Stylesheet = {
		'_': {
			color: 'red',
			position: Relative,
			padding: 4,
			margin: [0, "0.3em"]
		},
		'_::before': {
			content: '"[before] "'
		},
		'_ + _::before': {
			content: '"[before second item] "'
		},
		'$TestComponent + $OtherComponent': {
			textAlign: Center,
			// fontSize: css.GlobalValue.Inherit,
			// fontSize: GlobalValue.Inherit,
			fontSize: Inherit,
			fontWeight: 'bold',
			'--blargh': 42,
			zIndex: Var('blargh')
		}
	};

	override function render():ReactFragment {
		return <div className={className}>Test component</div>;
	}
}
