var Helpdesk = new function() {
  var self = this;
  
  self.updateTicketArea = function() {
    jQuery('#ticketTableContainer').children().remove();
    Tools.json ({ url: "/admin/api/helpdesk",
      method: "GET",
      callback: function(content) {
        var data = content['content'];
  
        var tableSource = new ChartDataSource;
        var table = new Chart;
  
        var cols = data['columns'];
        for (var i in cols) {
          tableSource.addColumn(cols[i]);
        }
  
        var rows = data['rows'];
        for (var i in rows) {
          tableSource.addRow(rows[i]);
        }
  
        table.setContainerID('ticketTableContainer');
        table.setDrawFunction(function(gTable,gData) {
          gTable.draw(gData, {showRowNumber:false,sortRow:3,sortAscending:true});
          google.visualization.events.addListener(gTable, 'select', function() {
            var selected = gTable.getSelection();
            for(var i = 0; i< selected.length; i++){
              var item = selected[i];
              if (item.row != null && gData.getValue(item.row,5) == 'click'){
                jQuery('input[name=lemail]').val(gData.getValue(item.row,1));
                jQuery('input[name=lticket]').val(gData.getValue(item.row,0));
                jQuery('#ticketForm').submit();
              }
            }
          });
        });
   
        table.setAPISpecificOptions({showRowNumber:false,sortRow:3,sortAscending:true});
        table.drawTable(tableSource);
        
      }
    });
  };
  
  self.newTicket = function() {
    var data = [];
    data.push(jQuery('input[name=pnp_user]').val());
    data.push(jQuery('input[name=type]').val());
    data.push(jQuery('input[name=name]').val());
    data.push(jQuery('select[name=pri]').val());
    data.push(jQuery('select[name=topicId]').val());
    data.push(jQuery('input[name=email]').val());
    data.push(jQuery('input[name=subject]').val());
    data.push(jQuery('textarea[name=message]').val());
    var validate = true;
  
    for (var i = 0; i < data.length; i++) {
      if (data[i] == "" || data[i] == null){
        validate = false;
      }
    }
    if (validate) {
      self.sendTicketData();
    } else {
      var overlay = '<div class="overlay" onClick="dismissOverlay()"><div class="overlayContent">';
      overlay += '<label class="badFields">Missing Required Fields!</label></div></div>';
      jQuery(overlay).insertAfter('#tabs');
    }
  }
  
  self.sendTicketData = function () {
    var dataString = {
    type: jQuery('input[name=type]').val(),
    name: jQuery('input[name=name]').val(),
    pri: jQuery('select[name=pri]').val(),
    topicId: jQuery('select[name=topicId]').val(),
    email: jQuery('input[name=email]').val(),
    phone: jQuery('input[name=phone]').val(),
    subject: jQuery('input[name=subject]').val(),
    message: jQuery('textarea[name=message]').val()};
  
    
    Tools.json({
     url: '/admin/api/helpdesk/',
     data: dataString,
     method: 'POST',
     callback: function(content) { 
       var data = content['content'];
       self.updateTicketArea();
       jQuery('#newHelpTicketForm input[name=lticket]').val(data["ticket"]);
       jQuery('#newHelpTicketForm input[name=lemail]').val(data["email"]);
       jQuery('#newHelpTicketForm').submit();
     },
     error: function() {
       alert('A ticketing error occured, try again!');
     }
    });
  };
};
