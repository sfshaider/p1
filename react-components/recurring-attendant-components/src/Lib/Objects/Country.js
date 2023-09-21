import getTools from './Tools'

class Country {
    _countries = [];

    constructor(common = '', two = '', three = '', numeric = '') {
        this._commonName = common;
        this._twoLetter = two;
        this._threeLetter = three;
        this._countryNumeric = numeric;
    };

    setCommonName = (commonName) => {
        this._commonName = commonName;
    };

    getCommonName = () => {
        return this._commonName;
    };

    setTwoLetter = (twoLetter) => {
        this._twoLetter = twoLetter;
    };

    getTwoLetter = () => {
        return this._twoLetter;
    };

    setThreeLetter = (threeLetter) => {
        this._threeLetter = threeLetter;
    };

    getThreeLetter = () => {
        return this._threeLetter;
    };

    setCountryNumeric = (numeric) => {
        this._countryNumeric = numeric;
    };

    getCountryNumeric = () => {
        return this._countryNumeric;
    };

    getCountries = () => {
        return this._countries;
    };

    loadCountries = (callbacks) => {
        const tools = getTools();

        tools.json({
            action: 'read',
            url: '/recurring/attendant/api/country',
            onSuccess: (data) => {
                const countryData = data['content']['countries'];
                countryData.map((country) => {
                    this._countries.push(new Country(country['commonName'], country['twoLetter'], country['threeLetter'], country['numeric']));
                });

                if (typeof(callbacks['success']) === 'function') {
                    callbacks['success'](this);
                }
            },
            onError: () => {
                if (typeof(callbacks['error']) === 'function') {
                    callbacks['error']();
                }
            }
        })
    };
}

export default Country;