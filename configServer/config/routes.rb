Authpuppy::Application.routes.draw do
  root to: "admins#login"
  post "create_login_session" => "admins#create_login_session"
  delete "logout" => "admins#logout", :as => "logout"

  resources :access_nodes
  get "access_nodes/:id/advanced" => "access_nodes#advanced", :as => "advance"
  get "access_nodes/:id/init" => "access_nodes#init", :as => "init"
  get "access_nodes/:id/firewall" => "access_nodes#firewall", :as => "firewall"
  post "access_nodes/setconfig" => "access_nodes#setconfig"

  get "ding" => "wifidog#ping"
  get "ping" => "wifidog#ping_task"
  get "api10/ping" => "wifidog#ping_zj"
  get "retrieve" => "wifidog#retrieve"
  get "fetchconf" => "wifidog#fetchconf"
  get "api10/taskrequest" => "wifidog#taskrequest"
  get "api10/taskresult" => "wifidog#taskresult"
  get "taskrequest" => "wifidog#taskrequest"
  get "gw_message.php" => "wifidog#denied"
  get "wifiauth" => "wifidog#auth"
  get "auth" => "wifidog#auth"
  get "api10/auth" => "wifidog#auth_zj"
  post "api10/upload" => "wifidog#upload"
  post "auth/login" => "wifidog#login"
  get "wifilogin" => "user#login"
  get "post/:aunnum" => "wifidog#authupdate"
  get "portal" => "user#portal"
  post "authenticate" =>"user#authenticate"
  get "logout/:token" =>"user#logout", :as => "offline"
  post "bindurl" =>"guest#bindurl"
  post "query_lat_long" => "access_nodes#query_lat_long"
  post "searchbymac" => "access_nodes#searchbymac"
  get "addnode" => "admins#addnode"
  post "addnode" => "admins#addnode"
  get "register" => "admins#register"
  post "register" => "admins#register"
  get "api10/register" => "admins#register"
  post "api10/register" => "admins#register"
  get "api10/login" => "user#login_zj"
  get "api10/portal" => "user#portal_zj"
  get "ict/portal" => "user#portal_ict"
  post "auth_update" => "auth#update"
  post "conf_update" => "conf#update"
  get "timeline" => "activity#timeline", :as => "timeline"
  post "showconnections" => "guest#show_connections"
  post "shownodes" => "guest#show_nodes"
  post "shownode" => "guest#show_node"
  post "addnodes" => "guest#addnodes"
  get "account/usernamevalidation" => "admins#usernamevalidation"
  get "devicenamevalidation" => "admins#devicenamevalidation"
  post "update_auth_type" => "guest#update_auth_type"
  post "update_auth_device" => "guest#update_auth_device"
  post "update_portal_url" => "guest#update_portal_url"
  post "update_access_time" => "guest#update_access_time"
  post "tmac_add" => "firewall#tmac_add"
  get  "tmac_del/:id" => "firewall#tmac_del", :as => "macdel"
  post "bmac_add" => "firewall#bmac_add"
  get  "bmac_del/:id" => "firewall#bmac_del", :as => "bmacdel"
  post "ip_add" => "firewall#ip_add"
  get  "ip_del/:id" => "firewall#ip_del", :as => "ipdel"
  get "indexconn" => "guest#index"
  post "sign_out" =>"user#sign_out", :as => "killline"

end
