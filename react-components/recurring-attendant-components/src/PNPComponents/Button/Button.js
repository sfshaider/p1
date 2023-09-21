import React, { Component } from 'react';
import { Transition } from 'react-transition-group';

/*
    This component renders a button with some text and a prop called stlying
    for the class name.
 */
const Button = ({ text, styling, click }) => {
    return (
        <button className="modalButton" style={styling} onClick={click}>{text}</button>
    )
};

const SVG = (props) => {
    return (
        <div
            className="svg-container"
            dangerouslySetInnerHTML={{__html: props.src}}>
        </div>
    )
};

/*
    This component loads and svg image from a url and then returns a button
    that can be animated with the svg.
 */
class AnimatedButton extends Component {
    constructor(props) {
        super(props);

        this.state = {
            animating: false,
            svg: null
        };
    }

    componentDidMount() {
        const { svgUrl } = this.props;
        fetch(svgUrl)
            .then(response => response.text())
            .then(data => this.setState({ svg: data }))
            .catch(error => console.log("Error --- unable to load SVG " + error));
    }

    onClickHandler = () => {
        this.setState({ animating: !this.state.animating }, () => this.props.click());
    };

    render() {
        return (
            <button style={this.props.styling} className="modalButton" onClick={this.onClickHandler} >
                {this.props.text + "  "}
                <Transition in={this.state.animating} timeout={1} unmountOnExit>
                    {() => (
                        <SVG src={this.state.svg}/>
                    )}
                </Transition>
            </button>
        )
    }
}

export { Button, AnimatedButton, SVG }