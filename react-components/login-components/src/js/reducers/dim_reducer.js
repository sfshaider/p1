import { UPDATE_WINDOW_DIMENSION } from '../actions/windowDimActions';
import WINDOW_DIMENSIONS from '../constants/windowDims';

const { TABLET, MOBILE } = WINDOW_DIMENSIONS;

const initialState = {
    width: window.innerWidth,
    height: window.innerHeight,
    isMobile: window.innerWidth <= MOBILE,
    isTablet: window.innerWidth <= TABLET,
};

const dimReducer = (state = initialState, action) => {
    Object.freeze(state);

    switch (action.type) {
        case UPDATE_WINDOW_DIMENSION:
            return {
                ...state,
                ...action.payload,
            };
        default:
            return state;
    }
};

export default dimReducer;
