package comp;

@:css('
	_ {
		color: red;
	}

	_::before {
		content: "[before] ";
	}

	_ + _::before {
		content: "[before second item] ";
	}

	_ + $OtherComponent {
		font-weight: bold;
	}
')
class TestComponent extends ReactComponent {
	override function render():ReactFragment {
		return <div className={className}>Test component</div>;
	}
}
