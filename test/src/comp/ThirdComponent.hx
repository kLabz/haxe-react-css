package comp;

@:css('
	_ {
		color: orange;
	}
')
@:css.priority(5)
class ThirdComponent extends ReactComponent {
	override function render():ReactFragment {
		return <div className={className}>Third component</div>;
	}
}
