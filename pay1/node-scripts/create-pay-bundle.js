var UglifyJS = require("uglify-js");
const fs = require('fs');

var files = [
  'pay1_home/web_common/_js/jquery-3.5.0/jquery-3.5.0.min.js',
  'pay1_home/web_common/_js/jquery-ui-1.13.2.custom/jquery-ui.min.js',
  'pay1_home/web_common/_js/Tools.js',
  'pay1_home/web/_js/DataValidation.js',
  'pay1_home/web/_js/Input.js',
  'pay1_home/web/_js/autoswipe.js',
  'pay1_home/web/_js/Pack.js',
  'pay1_home/web/_js/pay/pay.js',
  'pay1_home/web/_js/pay/masterpass.js',
  'pay1_home/web/_js/pay/amexexpress.js',
  'pay1_home/web/_js/AuthVia.js',
  'pay1_home/web/_js/CardinalCruise.js',
  'pay1_home/web/_js/integration/gocart.js'
];

var code = '';
for (i in files) {
  console.error("Bundling",files[i]);
  code = code + fs.readFileSync(files[i]);
}

var result = UglifyJS.minify(code);

console.log(result.code);
