var FAQ = new function() {
  
  var _searchTimer;
  var self = this;
  
  self.init = function() {
    jQuery('document').ready(function() {
      jQuery('#faqarea select[name=sections]').on('change',function() {
        self.search();
      });
    });
  }
  
  //Search for key words in FAQ issue
  self.search = function(){
    jQuery('#results').addClass('hidden');
    jQuery('#results').children().remove();
    jQuery('div[name=loader]').removeClass('hidden');
     window.clearTimeout(_searchTimer);
     _searchTimer = window.setTimeout(function() {
        self.AJAXSearch();
     },1000);
  
  };
  
  self.AJAXSearch = function(){ 
    var IDStamp = (new Date).getTime();
    var keywords = jQuery('#faqarea input[name=keywords]').val();
    var category = jQuery('#faqarea select[name=sections] option:selected').val();
    Tools.json({
      url: '/admin/api/faq/!/id/:' + IDStamp + '/keywords/:' + keywords + '/category/:' + category,
      method: "GET",
      callback: function(content) {
        var data = content['content'];
        self.loadTable(data);
      }
    });
  };

  self.displayOverlay = function (issueID) {
    var opts = {
      lines: 13,      // The number of lines to draw
      length: 20,     // The length of each line
      width: 10,      // The line thickness
      radius: 30,     // The radius of the inner circle
      scale: 1,       // Scales overall size of the spinner
      corners: 1,     // Corner roundness (0..1)
      rotate: 0,      // The rotation offset
      direction: 1,   // 1: clockwise, -1: counterclockwise
      color: '#EEE',  // #rgb or #rrggbb or array of colors
      speed: 1,       // Rounds per second
      trail: 60,      // Afterglow percentage
      shadow: false,  // Whether to render a shadow
      hwaccel: false,       // Whether to use hardware acceleration
      className: 'spinner', // The CSS class to assign to the spinner
      zIndex: 2e9,    // The z-index (defaults to 2000000000)
      top: '50%',     // Top position relative to parent
      left: '50%'     // Left position relative to parent
    };

    var wrapper = '<div class="overlay"><span id="loadingOverlay" onClick="dismissOverlay()"></span></div>';
    jQuery(wrapper).insertAfter('#tabs');
    var spinner = new Spinner(opts).spin(document.getElementById('loadingOverlay'));
    
    Tools.json({ url: '/admin/api/faq/:' + issueID,
      method:'GET',
      callback: function(content) {
        var data = content['content']['faq'];
        var overlay;
        var keyArray = jQuery('input[name=keywords]').val().split(",");
        if (data['issueID'] != null) {
          overlay = jQuery('div.overlayTemplate').clone().removeClass('overlayTemplate');
          var answer = data['answer'].replace(/&nbsp;/g," ").replace(/&#39;/g,"'").replace(/&amp;/g,'&').replace(/<br>/g, "\n");
          
          jQuery(overlay).find('div[name=issueID]').find('span').text(data['issueID']);
          jQuery(overlay).find('div[name=category]').find('span').text(data['sectionTitle']);
          jQuery(overlay).find('div[name=keywordList]').find('span').text(data['keywords'].replace(/&nbsp;/g," ").replace(/&#39;/g,"'").replace(/<br>/g,"\n").replace(/&amp;/g,'&'));
          jQuery(overlay).find('div[name=question]').find('span').text(data['question'].replace(/&nbsp;/g," ").replace(/&#39;/g,"'").replace(/<br>/g,"\n").replace(/&amp;/g,'&'));
          jQuery(overlay).find('div[name=answer]').find('span').text(answer);
          jQuery(overlay).removeClass('hidden').addClass('overlayContent');
        } else {
          overlay = jQuery('div.failureTemplate').clone().removeClass('failureTemplate');
          jQuery(overlay).find('span.failureID').text(issueID);
          jQuery(overlay).removeClass('hidden').addClass('overlayContent');
        }
        jQuery('#loadingOverlay').remove();
        jQuery('div.overlay').append(overlay).insertAfter('#tabs').fadeIn('fast');
      }
    });

  };

  
  self.loadTable = function (content) {
    jQuery('table.myCurrentSearch').parent().parent().remove();
    jQuery('table.myCurrentSearch').remove();
    var infoArray = content['response'];
    var data = new ChartDataSource;
    data.addColumn({type:'string',name: 'Category',id:'category'});
    data.addColumn({type: 'string',name: 'Issue ID',id: 'issue'});
    data.addColumn({type: 'string',name: 'Brief Description',id: 'descr'});

    for (var i in infoArray) {
      var issueInfo = infoArray[i];
      data.addRow(issueInfo);
    }

    var table = new Chart;
    table.setContainerID('results');
    table.setAPISpecificOptions({showRowNumber: false, height:'550px', width:'100%'});
    table.setDrawFunction( 
    function(gTable,info) {
      
      gTable.draw(info, {showRowNumber: false, height:'550px', width:'100%'});
      google.visualization.events.addListener(gTable, 'select', function() {
        var selected = gTable.getSelection();
        for(var i = 0; i< selected.length; i++){
          var item = selected[i];
          if (item.row != null){
            FAQ.displayOverlay(info.getValue(item.row,1));
          }
        }
      });
    });

    table.drawTable(data);
    jQuery('div[name=loader]').addClass('hidden');
    jQuery('#results').removeClass('hidden');
  
  };
};

FAQ.init();
