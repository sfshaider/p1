/*
-------------------------------------
Never Gonna Give You Up - Rick Astley
-------------------------------------
We're no strangers to love
You know the rules and so do I
A full commitment's what I'm thinking of
You wouldn't get this from any other guy
I just wanna tell you how I'm feeling
Gotta make you understand
Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you
We've known each other for so long
Your heart's been aching but you're too shy to say it
Inside we both know what's been going on
We know the game and we're gonna play it
And if you ask me how I'm feeling
Don't tell me you're too blind to see
Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you
Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you
Never gonna give, never gonna give
(Give you up)
(Ooh) Never gonna give, never gonna give
(Give you up)
We've known each other for so long
Your heart's been aching but you're too shy to say it
Inside we both know what's been going on
We know the game and we're gonna play it
I just wanna tell you how I'm feeling
Gotta make you understand
Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you
Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you
Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry

 */

import React, {Component} from 'react';
import { Transition } from 'react-transition-group';
import PropTypes from 'prop-types';
import "isomorphic-fetch";


class PNPButton extends Component {
    constructor(props) {
        super(props);

        this.state = {
            active: false,
            image: null
        }
    }

    getStates = () => {
        const { states } = this.props;
        const statesObject = {};

        for (let i in states) {
            const state = states[i];
            statesObject[state['state']] = state;
        }

        return statesObject;
    };

    componentDidMount() {
        // load the image from the url provided
        const states = this.getStates();

        if (states.active.image && states.active.image.src) { // only fetch if it is defined
            fetch(states.active.image.src)
                .then((response) => {
                    if (response.ok) {
                        return response.text()
                    } else {
                        return null;
                    }
                })
                .then((data) => {
                    this.setState({image: data})
                })
                .catch((error) => { console.log("--------- Error loading SVG: ", error) });
        }
    }

    onHandleButtonClick = (event) => {
        if (!this.state.active) {
            this.props.handleSubmit(event, () => {
                this.setState((prevState) => {
                    return {active: !prevState.active}
                });
            });
        }
    };

    render() {
        const duration = 1;
        // Need to accept props that determine weather text is to the left or right of image/svg
        const states = this.getStates();

        const submitStyle = { color: 'white', display: 'inline-block', margin: '10px' };
        const { active, image } = this.state;
        const currentState = (active ? states.active : states.normal);

        // set default text if none exists
        let textToPrint;
        if (active) {
            textToPrint = currentState.text || 'SUBMITTING'
        } else {
            // if the key amount is set and true in session data, and the path allows for payable button
            if ((currentState.amount && currentState.amount === "true") && this.props.payableButton) {
                textToPrint = this.props.amountText || 'SUBMIT';
            } else {
                textToPrint = currentState.text || 'SUBMIT'
            }
        }

        const rendered = (
            <div id="PNPButtonWrapper">
                <button style={{ cursor: 'pointer' }} disabled={this.props.disabled} id="customButton" onClick={(e) => { this.onHandleButtonClick(e) }}>
                    {(currentState.image === undefined || (currentState.image && (currentState.image.display === 'right' || currentState.image.display === undefined))) ?
                        <p style={submitStyle}>{textToPrint}</p> : null}
                    <Transition in={active} timeout={duration} unmountOnExit>
                        {() => (
                            !currentState.image ? null : currentState.image.type === 'svg' ? <SVG src={this.state.image}/> : <Image src={currentState.image.src}/>
                        )}
                    </Transition>
                    {(currentState.image && currentState.image.display === 'left') ? <p style={submitStyle}>{currentState.text}</p> : null}
                </button>
            </div>
        );

        return rendered;
    }
}

// don't like this at all
const SVG = (props) => {
    return (
        <div
            className="svg-container"
            dangerouslySetInnerHTML={{__html: props.src}}>
        </div>
    )
};

const Image = (props) => {
    const style = { width: '20px', height: '20px' };
    return (
        <img style={style} src={props.src}/>
    )
};

PNPButton.propTypes = {
    handleSubmit: PropTypes.func,
    settings: PropTypes.shape({
        src: PropTypes.string.isRequired,
        type: PropTypes.string.isRequired,
        alignment: PropTypes.string.isRequired,
    })
};

Image.propTypes = {
    src: PropTypes.string.isRequired
};


export default PNPButton;
