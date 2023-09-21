var BuyRates = new function() {
  var self = this;
  
  self.getRates = function () {
    var opts = {
      lines: 13,            // The number of lines to draw
      length: 5,           // The length of each line
      width: 3,             // The line thickness
      radius: 5,           // The radius of the inner circle
      scale: 1,             // Scales overall size of the spinner
      corners: 1,           // Corner roundness (0..1)
      rotate: 0,            // The rotation offset
      direction: 1,         // 1: clockwise, -1: counterclockwise
      color: '#EEE',        // #rgb or #rrggbb or array of colors
      speed: 1,             // Rounds per second
      trail: 60,            // Afterglow percentage
      shadow: false,        // Whether to render a shadow
      hwaccel: false,       // Whether to use hardware acceleration
      className: 'spinner', // The CSS class to assign to the spinner
      zIndex: 2e9,          // The z-index (defaults to 2000000000)
      top: 0,
      left:0
    };

    var spinner = new Spinner(opts).spin();
    jQuery('div.containerHeader').find('label').append(spinner.el);
    jQuery('div.containerHeader label').find('div.spinner').attr('style','');
    Tools.json({ url: '/admin/api/reseller/profile/:' + jQuery('#rates select[name=reseller_rates]').val() + '/buyrates/',
      method: 'GET',
      callback: function (content) {
        var data = content['content'];
        jQuery('#buyRatesContainer').children().remove();
        google.setOnLoadCallback(drawTable(data));
        jQuery('div.containerHeader label').find('div.spinner').remove();
      },
      error : function () {
        jQuery('#buyRatesContainer').children().remove();
        jQuery('div.containerHeader label').find('div.spinner').remove();
      }
    });
  };
};
