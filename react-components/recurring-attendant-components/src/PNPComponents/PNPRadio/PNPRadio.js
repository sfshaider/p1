import React from 'react';

const PNPRadio = (props) => {
    const radioContent = props.radio.map((element, idx) => {
        return (
            <span key={idx} className={"radioOption"}>
                <input onChange={element.onChange} id={element.name + idx} type='radio' checked={element.checked} value={element.value} name={element.name} />
                <label htmlFor={element.name + idx}>{element.text}</label>
            </span>
        )
    });

    return (
        <div className={"radioDiv"} style={{'display': 'inline'}}>
            {radioContent}
        </div>
    )
};

export default PNPRadio;
