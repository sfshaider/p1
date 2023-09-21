import React, { Component } from 'react';
import PropTypes from 'prop-types';
import { Link } from 'react-router-dom';


// import './PNPSidebar.css'
import '../../Themes/CardX/CardX.css';

export default class PNPSidebar extends Component {
    constructor(props) {
        super(props);

        this.state = {
            selectedElement: '',
            nav: 'closed'
        }
    };

    static propTypes = {
        content: PropTypes.array
    };

    static defaultProps = {
         content: []
    };

    render() {
        let classes = ["nav-bar"]

        if (this.props.navState === "open") {
            classes.push("open");
        }

        const classNames = classes.join(" ");


        const contentList = this.props.content.map((element, idx) => {
            return (
                <li key={idx} className={"nav-item"}>
                    <Link onClick={e => { this.props.change(e, element) }} to={element.path}>{element.title}</Link>
                </li>
            )
        })

        return (
            <div className={classNames}>
                <div className={"logo-box"}>
                    <img src={"https://d33afyne1i6b5q.cloudfront.net/assets/images/purple-logo.png"}/>
                </div>
                <ul>
                    <li key={"first-blank"} className={"nav-item"}></li>
                    {contentList}
                </ul>
            </div>
        )
    }
}
