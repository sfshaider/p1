import WINDOW_DIMENSIONS from '../constants/windowDims';

const { TABLET, MOBILE } = WINDOW_DIMENSIONS;

export const UPDATE_WINDOW_DIMENSION = 'UPDATE_WINDOW_DIMENSION';

export const updateWindowDimension = () =>
    (dispatch) => {
        return dispatch({
            type: UPDATE_WINDOW_DIMENSION,
            payload: {
                width: window.innerWidth,
                height: window.innerHeight,
                isMobile: window.innerWidth <= MOBILE,
                isTablet: window.innerWidth <= TABLET,
            },
        });
    }