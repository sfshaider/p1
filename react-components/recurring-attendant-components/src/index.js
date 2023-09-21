import 'babel-polyfill';
import React from 'react';
import ReactDOM from 'react-dom';
import './index.css';
import 'bootstrap/dist/css/bootstrap.min.css';
import '../src/Themes/CardX/CardX.css';
import Attendant from './Attendant';
import registerServiceWorker from './registerServiceWorker';

ReactDOM.render(<Attendant />, document.getElementById('root'));
registerServiceWorker();
