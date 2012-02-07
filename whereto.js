
            var map;

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
  
  
  load_data();
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
  var start_params = jQuery('#startdata').serialize();
  
  // Change icon/styling: http://docs.openlayers.org/library/feature_styling.html#styling
  
  var layer = new OpenLayers.Layer.Vector("WhereTo", {
                                            projection: map.displayProjection,
                                            //strategies: [new OpenLayers.Strategy.BBOX({resFactor: 1.1})],
                                            strategies: [new OpenLayers.Strategy.Fixed()],
                                            protocol: new OpenLayers.Protocol.HTTP({
                                                                                     //url: "/~theorb/cgi-bin/whereto.cgi?" + start_params,
                                                                                     url: "/~theorb/whereto/foo.tsv",
                                                                                     format: new OpenLayers.Format.Text()
                                                                                   })
                                            
                                          });
  
  map.addLayers([layer]);
  
  // FIXME: This doesn't really belong in load_data, but has
  // to be, because layer isn't in scope in init().  Should
  // really make the layer in init, but only populate it later.
  // Interaction; not needed for initial display.
  selectControl = new OpenLayers.Control.SelectFeature(layer);
  map.addControl(selectControl);
  selectControl.activate();
  layer.events.on({
                    'featureselected': onFeatureSelect,
                    'featureunselected': onFeatureUnselect,

                    'featuresadded': onFeaturesAdded
                  });


  
  return false;
}

