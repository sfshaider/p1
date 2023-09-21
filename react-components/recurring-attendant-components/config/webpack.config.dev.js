const path = require('path');

const HtmlWebpackPlugin = require('html-webpack-plugin');
const HtmlWebpackPluginConfig = new HtmlWebpackPlugin({
    template: './public/index.html',
    filename: 'index.html',
    inject: 'body'
});

module.exports = {
    entry: './src/index.js', // it is usually always this
    devServer: { // this tells webpack-dev-server to serve your content from the public dir
        publicPath: '/',
        contentBase: '/public',
    },
    // I dont think you even need the output on dev
    // because you will never run the build command here
    output: {
        path: path.join(__dirname, '../../pay1_home/react/_js/r'),
        filename: "recurringAttendant.js"
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
                            importLoaders: 1
                        }
                    }
                ]
            },
            {
                test: /\.(png|jpg|svg|woff|woff2|eot|ttf|otf)$/,
                use: [{
                    loader: 'file-loader',
                    options: {
                        limit: 8000,
                        name: '../../[name].[ext]'
                    }
                }]
            },
        ]
    },
    // add the plugin
    plugins: [HtmlWebpackPluginConfig]
};
