var Merchants = new function() {
  var self = this;
  var reseller;
  self.init = function() {
    /* load the subresellers for the logged in reseller */
    (function() {
      var jsonOptions = new Object();
      jsonOptions['key'] = 'subreseller';
      jsonOptions["action"] = "read";
      jsonOptions["url"] = "/admin/api/reseller/subreseller";
      jsonOptions["callback"] = function(data) {
          MerchantList.addSubresellerSelector(data,false);
          AddMerchant.addSubresellerSelector(data,false);
      };
      Tools.json(jsonOptions);
    }());
  }
}
