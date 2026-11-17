-- La sortie « Easy Effects Sink » est créée avec monitor.passthrough = true :
-- son volume (touches, Touch Bar, GNOME) n'est pas appliqué au son traité.
-- On le réactive à chaque apparition de la sortie (démarrage d'EasyEffects).
ee_sink_om = ObjectManager {
  Interest { type = "node", Constraint { "node.name", "=", "easyeffects_sink" } }
}
ee_sink_om:connect ("object-added", function (_, node)
  node:set_param ("Props", Pod.Object {
    "Spa:Pod:Object:Param:Props", "Props",
    params = Pod.Struct { "monitor.passthrough", false, "monitor.channel-volumes", true },
  })
  Log.info (node, "volume de la sortie EasyEffects réactivé")
end)
ee_sink_om:activate ()
