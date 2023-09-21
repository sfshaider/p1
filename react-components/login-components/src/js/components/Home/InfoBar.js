import React from 'react';
import classes from './InfoBar.css';

const infobar = () => {
    return (
      <div className={classes.InfoBar}>
          <div className={classes["InfoBar-spacer"]}>
              Call Us Today! 1-800-945-2538
              <span>|</span>
              <a href="mailto:sales@plugnpay.com">sales@plugnpay.com</a>
          </div>
      </div>
    );
}

export default infobar;