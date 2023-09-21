import React from 'react';
import classes from './Loader.css';

const loader = (props) => {
    const styles = {
        'visibility': `${props.visibility}`
    };

    return (
        <div style={styles} className={classes.Loader}></div>
    );
};

export default loader;