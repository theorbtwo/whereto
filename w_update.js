// Users markers_layer which is created in whereto.js

function update_tsv() {
  // gather form data, run whereto.pl via ajax, update with resulting filename
  var start_params = jQuery('#startdata').serialize();

  jQuery('#startdata').hide();
  jQuery('#ajaxload').show();
  jQuery.ajax({
                url: '/~theorb/whereto/whereto.pl',
                data: start_params,
                dataType: 'text',
                timeout: 1200*1000,
                success: set_tsv,
                error: ajax_error
              });
  
  return false;
}

function set_tsv(tsv_filename) {
  // set the layer url to '/~theorb/whereto/$tsv_filename

    markers_layer.protocol.options.url = "/~theorb/whereto/" + tsv_filename;
    strategy.refresh();
    
    markers_layer.loaded = false;
    markers_layer.setVisibility(true),
    markers_layer.refresh();

    markers_layer.redraw();

    jQuery('#startdata').show();
    jQuery('#ajaxload').hide();
}

function ajax_error() {
    jQuery('#startdata').show();
    jQuery('#ajaxload').hide();

    alert("Data fetch failed, probably timed out");
}