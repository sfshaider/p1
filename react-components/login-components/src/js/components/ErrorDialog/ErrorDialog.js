import React from 'react';
import classes from './ErrorDialog.css';

const errorDialog = (props) => {
	const cssClasses = [classes.ErrorDialog, props.isVisible ? classes.hide : classes.show];
	return (
		<div className={cssClasses.join(' ')}>
			{props.content}
			<button onClick={props.showOrHideDialog}>Dismiss</button>
		</div>
	);
};

export default errorDialog;