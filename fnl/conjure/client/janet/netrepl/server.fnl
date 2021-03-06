(module conjure.client.janet.netrepl.server
  {require {ui conjure.client.janet.netrepl.ui
            a conjure.aniseed.core
            net conjure.net
            log conjure.log
            trn conjure.client.janet.netrepl.transport
            config conjure.client.janet.netrepl.config}})

(defonce- state
  {:conn nil})

(defn- with-conn-or-warn [f opts]
  (let [conn (a.get state :conn)]
    (if conn
      (f conn)
      (ui.display ["# No connection"]))))

(defn display-conn-status [status]
  (with-conn-or-warn
    (fn [conn]
      (ui.display
        [(.. "# " conn.raw-host ":" conn.port " (" status ")")]
        {:break? true}))))

(defn disconnect []
  (with-conn-or-warn
    (fn [conn]
      (when (not (conn.sock:is_closing))
        (conn.sock:read_stop)
        (conn.sock:shutdown)
        (conn.sock:close))
      (display-conn-status :disconnected)
      (a.assoc state :conn nil))))

(defn- handle-message [err chunk]
  (let [conn (a.get state :conn)]
    (if
      err (display-conn-status err)
      (not chunk) (disconnect)
      (->> (conn.decode chunk)
           (a.run!
             (fn [msg]
               (log.dbg "receive" msg)
               (let [cb (table.remove (a.get-in state [:conn :queue]))]
                 (when cb
                   (cb msg)))))))))

(defn send [msg cb]
  (log.dbg "send" msg)
  (with-conn-or-warn
    (fn [conn]
      (table.insert (a.get-in state [:conn :queue]) 1 (or cb false))
      (conn.sock:write (trn.encode msg)))))

(defn- handle-connect-fn [cb]
  (vim.schedule_wrap
    (fn [err]
      (let [conn (a.get state :conn)]
        (if err
          (do
            (display-conn-status err)
            (disconnect))

          (do
            (conn.sock:read_start (vim.schedule_wrap handle-message))
            (send "Conjure")
            (display-conn-status :connected)))))))

(defn connect [host port]
  (let [host (or host config.connection.default-host)
        port (or port config.connection.default-port)
        resolved-host (net.resolve host)
        conn {:sock (vim.loop.new_tcp)
              :host resolved-host
              :raw-host host
              :port port
              :decode (trn.decoder)
              :queue []}]

    (when (a.get state :conn)
      (disconnect))

    (a.assoc state :conn conn)
    (conn.sock:connect resolved-host port (handle-connect-fn))))
