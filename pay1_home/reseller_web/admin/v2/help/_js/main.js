google.load('visualization','1', {packages:["table"]});

jQuery(document).ready(function() {
  //Filter tickets on load

  //Next to functions allow FAQ search to work
  jQuery('input[name=keywords]').on('keyup paste',function(){
    FAQ.search();
  });

  jQuery('select[name=searchDropdown]').change(function() {
    FAQ.search();
  });

  jQuery('input[name=idSearchButton]').click(function() {
    FAQ.displayOverlay(jQuery('#searchByID').val());
  });

  jQuery('input[name=newHelpTicket]').click(function() {
    Helpdesk.newTicket();
  });
  
  //Update my tickets by ticket status
  Tools.convertToGoogleTable({tableSelector:'#myTicketTable',callback:function (gTable,gData) {
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
  }});
});

function issueByID(){
  //Some fun div stuff
  jQuery('div[name=FAQSection]').addClass('hidden');
  jQuery('div[name=IssueIDSection]').removeClass('hidden');
}

function back(){
 //Some fun div stuff
 jQuery('div[name=FAQSection]').removeClass('hidden');
 jQuery('div[name=IssueIDSection]').addClass('hidden');
}

function dismissOverlay() {
  jQuery('div.overlay').fadeOut('fast').remove();
};

