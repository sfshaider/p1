import React, { Component } from 'react';
import { Provider } from 'react-redux';
import classes from './App.css';
import ReactDOM from 'react-dom';
import HomeWrapper from "./HomeWrapper";
import configureStore from '../../store/store';

class App extends Component {
    render() {
        return (
            <Provider store={configureStore()}>
                <div className={classes.App}>
                    <HomeWrapper />
                </div>
            </Provider>
        );
    }
}

ReactDOM.render(<App />, document.getElementById('root'));