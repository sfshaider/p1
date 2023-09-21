import React, {Component} from 'react';

const content = (props) => {
    return(
        <div className={"content"}>
            {props.children}
        </div>
    )
}

export default content;
