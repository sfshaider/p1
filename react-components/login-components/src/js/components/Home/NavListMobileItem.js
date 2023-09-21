import React, { useState } from 'react';
import classes from './NavListMobileItem.css';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faChevronDown } from '@fortawesome/free-solid-svg-icons';

const NavListMobileItem = ({ link='#', text, handleSubMenu, layer=1, hasSubMenu=false }) => {
    const renderLayerDashes = () => {
        return '-'.repeat(layer-1) + `${layer === 1 ? '' : ' '}`;
    };

    const layerClass = () => {
        switch(layer) {
            case 1:
                return "";
            case 2:
                return classes.MobileLayerTwo;
            case 3:
                return classes.MobileLayerThree;
            case 4:
                return classes.MobileLayerFour;
            default:
                return "";
        }
    };

    return (
        <div className={`${classes.MobileNavItem} ${layerClass()}`}>
            <a href={link}>{`${renderLayerDashes()}${text}`}</a>
            { hasSubMenu && <button onClick={handleSubMenu}>
                <FontAwesomeIcon icon={faChevronDown} />
            </button> }
        </div>
    );
};

export default NavListMobileItem;