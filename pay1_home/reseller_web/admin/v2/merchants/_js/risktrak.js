var RiskTrak = new function() {
  var risktrakSpinnerOptions = {
    lines: 13,            // The number of lines to draw
    length: 5,            // The length of each line
    width: 3,             // The line thickness
    radius: 5,            // The radius of the inner circle
    scale: 1,             // Scales overall size of the spinner
    corners: 1,           // Corner roundness (0..1)
    rotate: 0,            // The rotation offset
    direction: 1,         // 1: clockwise, -1: counterclockwise
    color: '#000',        // #rgb or #rrggbb or array of colors
    speed: 1,             // Rounds per second
    trail: 60,            // Afterglow percentage
    shadow: false,        // Whether to render a shadow
    hwaccel: false,       // Whether to use hardware acceleration
    className: 'spinner', // The CSS class to assign to the spinner
    zIndex: 2e9,          // The z-index (defaults to 2000000000)
    top: '0',             // Top position relative to parent
    left: '0'             // Left position relative to parent
  };

  var _merchant = '';
  var _requestPage = 0;
  var _requestPageLength = 500;


  self.init = function() {
    jQuery('document').ready(function() {
      jQuery('#exit').on('click',function() {
        var wrap = jQuery('#order-wrapper');
        wrap.slideUp();
      }

      _spinner = new Spinner(risktrakSpinnerOptions);
      jQuery('#spinner').append(spinner.el);

      jQuery('#historyFilter input[name=filter]').on('keyup', function() {
        if (typeof(filterTimer) != 'undefined') {
          clearTimeout(filterTimer);
        }
          filterTimer = setTimeout(function() {
          filterHistory();
        }, 250);
      });
    });
  }

  self.startSpinner = function() {
    _spinner.spin();
  }

  self.stopSpinner = function() {
    _spinner.stop();
  }

  self.loadSettings = function() {
    json({
           'url': '/admin/api/reseller/merchant/:' + _merchant + '/risktrak/settings',
        'action': 'read',
           'key': 'risktrakSettings',
      'callback': function(data) {
                    // do something with data here
                  }
    });
  }

  self.loadStats = function() {
    json({
           'url': '/admin/api/reseller/merchant/:' + _merchant + '/risktrak/stats',
        'action': 'read',
           'key': 'risktrakStats',
      'callback': function(data) {
                     // do something with data here
                  }
    });
  }

  self.loadHistory = function() {
    json({
           'url': '/admin/api/reseller/merchant/:' + _merchant + '/risktrak/history',
        'action': 'read',
           'key': 'risktrakHistory',
      'callback': function(data) {
                    // do something with data here
                  }
    });

  self.loadTransaction = function(orderID) {
    json({
           'url': '/admin/api/reseller/merchant/:' + _merchant + '/transaction/:' + orderID,
        'action': 'read',
           'key': 'transaction',
      'callback': function(data) {
                    // do something with data here
                  }
    });
  }
}
