const path = require('path');

module.exports = {
    entry: {
        login: './src/js/components/Home/App.js',
    },
    output: {
        path: path.join(__dirname, '../../pay1_home/react/_js/r'),
        filename: "[name].js",
        publicPath: "_js/r/",
        chunkFilename: '[id].[chunkhash].js'
    },
    module: {
        rules: [
            {
                test: /\.js$/,
                exclude: /node_modules/,
                use: {
                    loader: 'babel-loader',
                    query: {
                        presets: ['@babel/env', '@babel/react'],
                        plugins: ['transform-class-properties']
                    }
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
                            modules: {
                                localIdentName: '[name]__[local]__[hash:base64:5]'
                            }
                        }
                    }
                ]
            },
            {
                test: /\.(png|jpg|svg)$/,
                use: [{
                    loader: 'file-loader',
                    options: {
                        limit: 8000,
                        name: 'public/[hash]-[name].[ext]'
                    }
                }]
            },
        ]
    },
};
