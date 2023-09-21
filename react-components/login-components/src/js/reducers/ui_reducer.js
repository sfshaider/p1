import { combineReducers } from "redux";
import dimReducer from "./dim_reducer";

const uiReducer = combineReducers({
    dimensions: dimReducer,
});

export default uiReducer;
