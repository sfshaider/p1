const path = require('path');

module.exports = {
    entry: {
        recurringAttendant: './src/index.js',
    },
    output: {
        path: path.join(__dirname, '../../../pay1_home/react/_js/r'),
        filename: "[name].js",
        publicPath: "_js/r/",
        chunkFilename: '[id].[chunkhash].js'
    },
    module: {
        rules: [
            {
                test: /\.js$/,
                loader: 'babel-loader',
                exclude: /node_modules/,
                query: {
                    presets: ['react', 'es2015'],
                    plugins: ['transform-class-properties']
                }

            },
            {
                test: /\.html$/,
                use: [
                    {
                        loader: "html-loader"
                    }
                ]
            },
            {
                test: /\.css$/,
                use: [
                    require.resolve('style-loader'),
                    {
                        loader: require.resolve('css-loader'),
                        options: {
                            importLoaders: 1,
                        }
                    }
                ]
            },
            {
                test: /\.(png|jpg|svg|woff|woff2|eot|ttf|otf)$/,
                use: [{
                    loader: 'file-loader',
                    options: {
                        name: '../../[name].[ext]'
                    }
                }]
            },
        ]
    },
};

