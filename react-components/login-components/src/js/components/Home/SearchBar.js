import React, { useState } from 'react';
import classes from './SearchBar.css';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faSearch, faTimes } from '@fortawesome/free-solid-svg-icons';

const SearchBar = props => {
    const [searchText, setSearchText] = useState("");

    const handleInput = e => {
        e.preventDefault();
        setSearchText(e.target.value);
    };

    const handleSubmitEnter = e => {
        if (e.key === 'Enter') {
            handleSubmit();
        }
    };

    const handleSubmit = () => {
        if (searchText.length >= 1) {
            window.location.href = `https://www.plugnpay.com/?s=${searchText}`;
        }
    };
    
    const handleEmpty = e => {
        e.preventDefault();
        setSearchText("");
    };

    return (
        <div className={classes["search-bar-container"]}>
            <div className={classes["search-bar-innerbox"]}>
                <input 
                    type='text'
                    className={classes["search-bar-input"]}
                    name='searchBar'
                    onChange={handleInput}
                    onKeyDown={handleSubmitEnter}
                    value={searchText}
                    placeholder="Search..."
                />
                <FontAwesomeIcon icon={faSearch} className={classes["search-bar-icon"]} onClick={handleSubmit} />
                {searchText.length >= 1 && 
                    <FontAwesomeIcon icon={faTimes} className={classes["search-bar-empty"]} onClick={handleEmpty} />}
            </div>
        </div>
    );
};

export default SearchBar;
