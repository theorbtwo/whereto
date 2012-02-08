
var map;
var markers_layer;
var strategy = new OpenLayers.Strategy.Refresh({force: true, active: true});

var click_mode = 'select';

// Various projection/centring messing courtesy of:
// http://openlayers.org/dev/examples/sundials-spherical-mercator.html

function init(){
  map = new OpenLayers.Map({
                             div: 'map',
                             projection: new OpenLayers.Projection("EPSG:900913"),
                             displayProjection: new OpenLayers.Projection("EPSG:4326"),
                             units: "m",
                             maxResolution: 156543.0339,
                             maxExtent: new OpenLayers.Bounds(
                                 -20037508, -20037508, 20037508, 20037508.34
                             )
                           });
  
  map.addControl(new OpenLayers.Control.LayerSwitcher());
  map.addControl(new OpenLayers.Control.PanZoomBar() );
  
  var osm = new OpenLayers.Layer.OSM();
  var gmap = new OpenLayers.Layer.Google("Google Streets", {visibility: false});
  map.addLayers([osm, gmap]);
  
  map.setCenter(
    new OpenLayers.LonLat(-6.32894, 52.800525).transform(
      new OpenLayers.Projection("EPSG:4326"),
      map.getProjectionObject()
    ), 
    6
  );
  
  // See http://openlayers.org/dev/examples/click.html
  OpenLayers.Control.Click = OpenLayers.Class(OpenLayers.Control, {                
                                                defaultHandlerOptions: {
                                                  'single': true,
                                                  'double': false,
                                                  'pixelTolerance': 0,
                                                  'stopSingle': false,
                                                  'stopDouble': false
                                                },
                                                
                                                initialize: function(options) {
                                                  this.handlerOptions = OpenLayers.Util.extend(
                                                    {}, this.defaultHandlerOptions
                                                  );
                                                  OpenLayers.Control.prototype.initialize.apply(
                                                    this, arguments
                                                  ); 
                                                  this.handler = new OpenLayers.Handler.Click(
                                                    this, {
                                                      'click': this.trigger
                                                    }, this.handlerOptions
                                                  );
                                                }, 
                                                
                                                trigger: function(e) {
                                                  if (click_mode == 'passthrough') {
                                                    return true;
                                                  }

                                                  var map_proj = map.getProjectionObject();

                                                  var lonlat = map.getLonLatFromViewPortPx(e.xy);
                                                  lonlat.transform(map_proj, new OpenLayers.Projection("EPSG:4326"));

                                                  jQuery("#id_latitude").val(lonlat.lat);
                                                  jQuery("#id_longitude").val(lonlat.lon);

                                                  return false;
                                                }
                                              });

  var click = new OpenLayers.Control.Click();
  map.addControl(click);
  click.activate();
  
  load_data();
}



function onClick(evt) {
  
}

// Needed only for interaction, not for the display.
function onPopupClose(evt) {
  // 'this' is the popup.
  selectControl.unselect(this.feature);
}

function onFeatureSelect(evt) {
  feature = evt.feature;
  popup = new OpenLayers.Popup.FramedCloud("featurePopup",
                                           feature.geometry.getBounds().getCenterLonLat(),
                                           new OpenLayers.Size(100,100),
                                           "<h2>"+feature.attributes.title + "</h2>" +
                                           feature.attributes.description,
                                           null, true, onPopupClose);
  feature.popup = popup;
  popup.feature = feature;
  map.addPopup(popup);
}

function onFeatureUnselect(evt) {
  feature = evt.feature;
  if (feature.popup) {
    popup.feature = null;
    map.removePopup(feature.popup);
    feature.popup.destroy();
    feature.popup = null;
  }
}

function onFeaturesAdded(evt) {
  // http://dev.openlayers.org/docs/files/OpenLayers/Map-js.html#OpenLayers.Map.zoomToExtent
  layer = evt.features[0].layer;
  layer.map.zoomToExtent(layer.getDataExtent());
}

function load_data() {
  // Change icon/styling: http://docs.openlayers.org/library/feature_styling.html#styling
  
  markers_layer = new OpenLayers.Layer.Vector("WhereTo", {
                                                projection: map.displayProjection,
                                                //strategies: [new OpenLayers.Strategy.BBOX({resFactor: 1.1})],
      strategies: [new OpenLayers.Strategy.Fixed, strategy],
                                                protocol: new OpenLayers.Protocol.HTTP({
                                                                                         //url: "/~theorb/cgi-bin/whereto.cgi?" + start_params,
//                                                                                         url: "/~theorb/whereto/data-files/51.584483-1.7415850.5.tsv",
                                                                                         url: "about:blank",
                                                                                         format: new OpenLayers.Format.Text()
                                                                                       })
                                                
                                              });
  
//    strategy.activate();
  map.addLayers([markers_layer]);
  
  // FIXME: This doesn't really belong in load_data, but has
  // to be, because layer isn't in scope in init().  Should
  // really make the layer in init, but only populate it later.
  // Interaction; not needed for initial display.
  selectControl = new OpenLayers.Control.SelectFeature(markers_layer);

  map.addControl(selectControl);
  selectControl.activate();

  markers_layer.events.on({
                            'featureselected': onFeatureSelect,
                            'featureunselected': onFeatureUnselect,
                            
                            'featuresadded': onFeaturesAdded
                          });


  
  return false;
}


jQuery(document).ready(function() {
    jQuery('#startdata').submit(update_tsv);
});

