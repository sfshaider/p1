import React, { useState }  from 'react';
import Logo from './Logo';
import classes from './Nav.css';
import NavList from './NavList';
import { connect } from 'react-redux';
import NavListMobile from './NavListMobile';
import SearchBar from './SearchBar';

const Nav = ({ loginType, update, dimensions }) => {
    const { isTablet } = dimensions;
    const [mobileNav, setMobileNav] = useState(false);
    const [searchMobile, setSearchMobile] = useState(false);

    const handleSetMobileNav = e => {
        e.preventDefault();
        setMobileNav(!mobileNav);
    };

    const handleSetSearchMobile = e => {
        e.preventDefault();
        setSearchMobile(!searchMobile);
    };

    return (
        <div className={classes.Nav}>
            <div className={classes["Nav-spacer"]}>
                <Logo logoUrl="../_js/r/public/a8d46688b2bcfcbadf5e195848b368d2-pnpbg.jpg"/>
                <NavList
                    loginType={loginType}
                    update={update}
                    dimensions={dimensions}
                    handleSetMobileNav={handleSetMobileNav}
                    handleSetSearchMobile={handleSetSearchMobile}
                />
            </div>
            <NavListMobile update={update} show={isTablet && mobileNav} />
            {(isTablet && searchMobile) && <SearchBar />}
        </div>
    );
}

const mapStateToProps = state => ({
    dimensions: state.ui.dimensions,
});
const mapDispatchToProps = null;

export default connect(mapStateToProps, mapDispatchToProps)(Nav);
