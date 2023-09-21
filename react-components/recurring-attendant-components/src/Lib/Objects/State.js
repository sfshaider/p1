import getTools from './Tools'

class State {
    _states = [];

    constructor(abbreviation = '', commonName = '') {
        this._abbreviation = abbreviation;
        this._commonName = commonName;
    };

    setCommonName = (commonName) => {
        this._commonName = commonName;
    };

    getCommonName = () => {
        return this._commonName;
    };

    setAbbreviation = (abbreviation) => {
        this._abbreviation = abbreviation;
    };

    getAbbreviation = () => {
        return this._abbreviation;
    };

    getStates = () => {
        return this._states;
    };

    loadStates = (country, callbacks) => {
        const tools = getTools();

        tools.json({
            action: 'read',
            url: '/recurring/attendant/api/country/:' + country + '/state',
            onSuccess: (data) => {
                const stateData = data['content']['states'];
                stateData.map((state) => {
                    this._states.push(new State(state['abbreviation'], state['commonName']));
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

export default State;