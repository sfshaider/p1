import React from 'react';
import classes from './Logo.css';

const logo = (props) => {
    return (
        <div className={classes.Logo}>
            <a href="https://www.plugnpay.com"><img src={props.logoUrl} alt="Corp. Logo."/></a>
        </div>
    );
}

export default logo;