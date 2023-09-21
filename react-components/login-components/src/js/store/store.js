import { createStore, applyMiddleware, compose } from 'redux';
import thunk from 'redux-thunk';
import RootReducer from '../reducers/root_reducer';

const composeEnhancers = window.__REDUX_DEVTOOLS_EXTENSION_COMPOSE__ || compose;
const enhancer = composeEnhancers(applyMiddleware(thunk));

const configureStore = (preloadedState = {}) => {
    return createStore(
        RootReducer,
        preloadedState,
        enhancer
    );
};

export default configureStore;