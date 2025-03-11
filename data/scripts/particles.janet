# Saved for later:
#
# :get-spawn-params (fn [self ticks ctx coord target]
#                     (let [diffx  (- (target :x) (coord :x))
#                           diffy  (- (target :y) (coord :y))
#                           angle  (math/atan2 diffy diffx)
#                           dist   (:distance coord target)
#                           offset [(rad 90) (rad -90) (rad 180)]
#                           nangle (+ angle (offset (% (self :total-spawned) 2)))
#                           ntarg  (new-coord (+ (coord :x) (* dist (math/cos nangle)))
#                                             (+ (coord :y) (* dist (math/sin nangle))))]
#                       [ntarg coord]))
#
# Effect: when spliced into flamethrower effect, causes three beams of fire to
# shoot at target: one from the source, the other two from a few tiles away. A
# bit of a "backwards ray", spreading in instead of out.
#

(def PLAYER_LOS_R 8)

(def SYMB1_CHARS "~!@#$%^&*()[]\\{}|/<>?;:1234567890")
(def ROUND_CHARS "oO0@CQ") # Unicode not supported :( "°ØøÖÓÕÔŌQCÇ"
(def POINT_CHARS "XVNMLWTEFZ")
(def ASCII_CHARS "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`1234567890-=~!@#$%^&*()_+[]\\{}|;':\",./<>?")

(def CONCRETE 0x9f8f74)
(def LIGHT_CONCRETE 0xefdfc4)
(def GOLD 0xddb733)
(def DARK_GOLD  0x442700)
(def LIGHT_GOLD 0xfdd753)
(def ELEC_BLUE1 0x9fefff)
(def ELEC_BLUE2 0x7fc7ef)
(def GREEN 0x57cf00)
(def VDARK_GREEN 0x075f00)
(def LIGHT_GREEN 0x37af00)
(def BG 0x0f0e0b)
(def FIRE_COLORS [
  #0xFFFFFF 0xEFEFC7 0xDFDF9F 0xCFCF6F 0xB7B737 0xB7AF2F 0xBFAF2F 0xBFA727
  #0xEEEEEE 0xEEEEEE 0xEEEEEE 0xEEEEEE 0xEEEEEE 0xEEEEEE 0xEEEEEE 0xEEEEEE
  #0xBFA727 0xBF9F1F 0xBF9F1F 0xC7971F 0xC78F17 0xC78717 0xCF8717 0xCF7F0F
  #0xCF770F 0xCF6F0F 0xD7670F 0xD75F07 0xDF5707 0xDF5707 0xDF4F07 0xC74707
  #0xBF4707 0xAF3F07 0x9F2F07 0x8F2707 0x771F07 0x671F07 0x571707 0x470F07
  #0x2F0F07 0x1F0707 0x070707
  0x431000
  0xae2b00
  0xe43700
  0xff5200
  0xff5803
  0xff6a00
  0xff9f00
  0xffff00
])

(defn panic [msg & args]
  (eprintf msg ;args)
  (assert false))

# From spork.
(defn shuffle-in-place
  ```
  Generate random permutation of the array `xs`
  which is shuffled in place.
  ```
  [xs]
  (var xl (length xs))
  (var t nil)
  (var i nil)
  (while (pos? xl)
    (set i (math/rng-int (math/rng (os/time)) xl))
    (-- xl)
    (set t (xs xl))
    (set (xs xl) (xs i))
    (set (xs i) t))
  xs)

# TODO: remove if this is accepted into the stdlib and when the next version of
# Janet is released.
(defn deepclone [x]
  (case (type x)
    :array (array/slice (map deepclone x))
    :tuple (tuple/slice (map deepclone x))
    :table (if-let [p (table/getproto x)]
             (deepclone (merge (table/clone p) x))
             (table ;(map deepclone (kvs x))))
    :struct (struct ;(map deepclone (kvs x)))
    :buffer (buffer x)
    x))

(defn lerp [a b mu]
  (math/floor (+ a (* mu (- b a)))))

(defn random-choose [array]
  (array (math/floor (* (math/random) (length array)))))

(defn rad [deg]
  (* (/ (% deg 360) 180) math/pi))

(def Coord @{
             :x 0 :y 0                                   # Can be fractional.
             :eq? (fn [a b]
                    (and (= (math/round (a :x)) (math/round (b :x)))
                         (= (math/round (a :y)) (math/round (b :y)))))
             :distance (fn [a b] # Chebyshev
                         (let [diffx (math/abs (- (a :x) (b :x)))
                               diffy (math/abs (- (a :y) (b :y)))]
                           (max diffx diffy)))
             :distance-euc (fn [a b]
                             (let [diffx (math/abs (- (a :x) (b :x)))
                                   diffy (math/abs (- (a :y) (b :y)))]
                               (math/sqrt (+ (* diffx diffx) (* diffy diffy)))))
             :angle (fn [a b]
                      (let [diffx  (- (a :x) (b :x))
                            diffy  (- (a :y) (b :y))]
                            (math/atan2 diffy diffx)))
             :move-angle (fn [self r t]
                           (var new (table/clone self))
                           (put new :x (+ (self :x) (* r (math/cos t))))
                           (put new :y (+ (self :y) (* r (math/sin t))))
                           new)
             :move (fn [a direction]
                     (var new (table/clone a))
                     (case direction
                       :nw
                         (do
                           (put new :x (- (a :x) 1))
                           (put new :y (- (a :y) 1)))
                       :n
                         (put new :y (- (a :y) 1))
                       :ne
                         (do
                           (put new :x (+ (a :x) 1))
                           (put new :y (- (a :y) 1)))
                       :e
                         (put new :x (+ (a :x) 1))
                       :w
                         (put new :x (- (a :x) 1))
                       :sw
                         (do
                           (put new :x (- (a :x) 1))
                           (put new :y (+ (a :y) 1)))
                       :s
                         (put new :y (+ (a :y) 1))
                       :se
                         (do
                           (put new :x (+ (a :x) 1))
                           (put new :y (+ (a :y) 1)))
                       (assert false))
                     new)
             })
(defn new-coord [&opt x y]
  (default x 0)
  (default y 0)
  (table/setproto @{ :x x :y y } Coord))

(def Rect @{
             :start (new-coord)
             :height 0
             :width 0
             :contains? (fn [self coord]
                          (and
                            (>= (coord :x) ((self :start) :x))
                            (>= (coord :y) ((self :start) :y))
                            (< (coord :x) (+ ((self :start) :x) (self :width)))
                            (< (coord :y) (+ ((self :start) :y) (self :height)))))
             :center (fn [self]
                       (new-coord (+ ((self :start) :x) (/ (self :width) 2))
                                  (+ ((self :start) :y) (/ (self :height) 2))))
             })
(defn new-rect [&opt start width height]
  (default start (new-coord))
  (default width 0)
  (default height 0)
  (table/setproto @{ :start start :width width :height height } Rect))

(def Tile @{ :ch " " :fg 0xffffff :bg BG :bg-mix 0.8 })
(defn new-tile [table] (table/setproto table Tile))

# Used by Particle, so must be defined before it
(defn get-parent [self recurse]
  (if (= recurse 0)
    self
    (get-parent (self :parent) (- recurse 1))))

(def Particle @{
                :tile (new-tile @{})
                :speed 1
                :coord (new-coord)
                :initial-coord (new-coord)
                :target (new-coord)
                :triggers @[]
                :lifetime nil
                :territorial false
                :require-los 1
                :require-nonwall true
                :filter (fn [self ticks ctx] false)

                :id 0
                :parent nil
                :dead false
                :original-tile nil
                :age 0

                :tick (fn [self ticks ctx]
                        # Update particle position
                        (let [diffx (- ((self :target) :x) ((self :coord) :x))
                              diffy (- ((self :target) :y) ((self :coord) :y))
                              angle (math/atan2 diffy diffx)
                              # Don't move past target
                              speed (min (math/sqrt (+ (* diffx diffx) (* diffy diffy))) (self :speed))]
                          (+= ((self :coord) :x) (* speed (math/cos angle)))
                          (+= ((self :coord) :y) (* speed (math/sin angle))))

                        (each trigger (self :triggers)
                          (if trigger (do
                            (def conditions (slice trigger 0 (- (length trigger) 1)))
                            (def action     (trigger (- (length trigger) 1)))
                            (var satisfies-conditions true)
                            (each trigger-cond conditions
                              (if (not ((trigger-cond 0) self ticks ctx ;(slice trigger-cond 1)))
                                (do
                                  (set satisfies-conditions false)
                                  (break))))
                            (if satisfies-conditions
                              ((action 0) self ticks ctx ;(slice action 1))))))
                        (++ (self :age))

                        (or (not (:contains? (ctx :bounds) (self :coord)))
                            (and (> (self :speed) 0) (:eq? (self :coord) (self :target)))
                            (>= (self :age) (or (self :lifetime) 99999))))

                :get-lifetime (fn [self &] (self :lifetime))
                :completed-journey (fn [self &opt factor]
                                     (default factor 1)
                                     (let [orig-dist (:distance (self :initial-coord) (self :target))
                                           curr-dist (:distance (self :coord) (self :target))]
                                       (if (or (= orig-dist 0)
                                               (< (- orig-dist curr-dist) 1))
                                         (break 0))
                                       (/ (- orig-dist curr-dist) (* factor orig-dist))))

                :COND-true (fn [&] true)
                :COND-nth-tick (fn [self ticks ctx n] (= (% ticks n) 0))
                :COND-completed-journey-percent-is? (fn [self ticks ctx func rvalue]
                                                      (func (/ (:distance (self :target) (self :coord))
                                                               (:distance (self :target) (self :initial-coord)))
                                                            rvalue))
                :COND-lifetime-complete? (fn [self &]
                                           (= (self :age) (- (self :lifetime) 1)))
                :COND-parent-dead? (fn [self ticks ctx recurse &]
                                     (let [parent (get-parent self recurse)]
                                       (parent :dead)))
                :COND-reached-target? (fn [self ticks ctx bool &]
                                        (= bool (:eq? (self :coord) (self :target))))
                :COND-explosion-still-expanding? (fn [self ticks ctx parent]
                                                   (not ((get-parent self parent) :explosion-finished-expanding)))
                :COND-explosion-done-expanding? (fn [self ticks ctx parent]
                                                   ((get-parent self parent) :explosion-finished-expanding))
                :COND-percent? (fn [self ticks ctx percent]
                                 (< (* (math/random) 101) percent))
                :COND-custom (fn [self ticks ctx func & args]
                               (func self ticks ctx ;args))

                :TRIG-custom (fn [self ticks ctx func & args]
                               (func self ticks ctx ;args))
                :TRIG-reset-original-tile (fn [self ticks ctx]
                                            (put self :original-tile (deepclone (self :tile))))
                :TRIG-reset-lifetime-once (fn [self ticks ctx p-new-lifetime new-age]
                                            (if (not (self :lifetime))
                                              (do
                                                (def new-lifetime
                                                  (case (type p-new-lifetime)
                                                    :number p-new-lifetime
                                                    :function (p-new-lifetime self ticks ctx)))
                                                (put self :lifetime new-lifetime)
                                                (put self :age new-age))))
                :TRIG-set-speed (fn [self ticks ctx new-speed]
                                  (case (type new-speed)
                                    :number (put self :speed new-speed)
                                    :function (put self :speed (new-speed self ticks ctx))))
                :TRIG-cycle-glyph (fn [self ticks ctx chars &]
                                    (assert (= (type chars) :string))
                                    (def current ((self :tile) :ch))
                                    (var current-index nil)
                                    (loop [i :range [0 (length chars)]]
                                      (if (= (string/from-bytes (chars i)) current)
                                        (do (set current-index i)
                                            (break))))
                                    (if (not current-index)
                                      (break))
                                    (def new-index (% (+ current-index 1) (length chars)))
                                    (put (self :tile) :ch (string/from-bytes (chars new-index))))
                :TRIG-scramble-glyph (fn [self ticks ctx chars &]
                                       (def new-char (random-choose chars))
                                       (case (type chars)
                                         :string (put (self :tile) :ch (string/from-bytes new-char))
                                         :tuple  (put (self :tile) :ch new-char)))
                :TRIG-set-glyph (fn [self ticks ctx how]
                                  (def new
                                    (case (how 0)
                                      :overall-cardinal-angle
                                        (let [diffx (- ((self :target) :x) ((self :initial-coord) :x))
                                              diffy (- ((self :target) :y) ((self :initial-coord) :y))
                                              angle (% (+ 360 (/ (* (math/atan2 diffy diffx) 180) math/pi)) 360)]
                                          (cond
                                            (and (>= angle  45) (<= angle 135)) ((how 1) 0) # NORTH
                                            (and (>= angle 135) (<= angle 225)) ((how 1) 3) # WEST
                                            (and (>= angle 225) (<= angle 315)) ((how 1) 1) # SOUTH
                                            (or  (<= angle  45) (>= angle 315)) ((how 1) 2) # EAST
                                            "X"))))
                                  (put (self :tile) :ch new))
                :TRIG-modify-color (fn [self ticks ctx which rgb? how &named inverse]
                                     (default inverse false)
                                     (def origtile (self :original-tile))
                                     (def curtile  (self :tile))
                                     (var [color1 factor]
                                       (case (how 0)
                                         :custom # (:custom :curtile|:origtile (func...))
                                           [(case (how 1) :curtile curtile :origtile origtile) ((how 2) self ticks ctx)]
                                         :random-factor
                                           [curtile (+ (* (math/random) (- (how 2) (how 1))) (how 1))]
                                         :fixed-factor
                                           [curtile (how 1)]
                                         :completed-journey
                                           (let [orig-dist (:distance (self :initial-coord) (self :target))
                                                 curr-dist (:distance (self :coord) (self :target))]
                                             [origtile (/ (- curr-dist 0) (+ 0.0001 (* 1 orig-dist)))])
                                         :completed-parent-lifetime # (:completed-parent-lifetime parent-recurse factor)
                                           (let [parent (get-parent self (how 1))]
                                             #(eprint "parent-age: " (parent :age) "; parent-lifetime: " (parent :lifetime))
                                             [origtile (min 1 (- 1 (/ (parent :age) (* (how 2) (:get-lifetime parent ticks ctx)))))])
                                         :completed-lifetime # (:completed-lifetime factor)
                                             [origtile (max 0 (min 1 (- 1 (/ (self :age) (+ 0.00001 (* (how 1) (self :lifetime)))))))]))
                                     (if inverse
                                       (set factor (- 1 factor)))
                                     (var r (band (brshift (color1 which) 16) 0xFF))
                                     (var g (band (brshift (color1 which)  8) 0xFF))
                                     (var b (band (brshift (color1 which)  0) 0xFF))
                                     (var a (color1 :bg-mix))
                                     (if (string/find "r" rgb?) (set r (math/floor (min 255 (* r factor)))))
                                     (if (string/find "g" rgb?) (set g (math/floor (min 255 (* g factor)))))
                                     (if (string/find "b" rgb?) (set b (math/floor (min 255 (* b factor)))))
                                     (if (string/find "a" rgb?) (set a (max 0 (min 1.0 (* a factor)))))
                                     (put (self :tile) which (bor (blshift r 16) (blshift g 8) b))
                                     (put (self :tile) :bg-mix a))
                :TRIG-lerp-color (fn [self ticks ctx which color2 rgb? how &named inverse]
                                   (default inverse false)
                                   (var factor
                                     (case (how 0)
                                       :custom
                                           ((how 1) self ticks ctx)
                                       :sine-custom # (:sine (fn [self ticks ctx] ...))
                                           (/ (+ (math/sin (rad ((how 1) self ticks ctx))) 1) 2)
                                       :completed-lifetime # (:completed-lifetime factor)
                                           (min 1 (- 1 (/ (self :age) (* (how 1) (self :lifetime)))))

                                       # TODO: use and test with (:completed-journey Particle) instead of
                                       # duplicating the logic here
                                       #
                                       # (there are minor differences in the way potential divide-by-zeros are handled)
                                       :completed-journey
                                         (let [orig-dist (:distance (self :initial-coord) (self :target))
                                               curr-dist (:distance (self :coord) (self :target))]
                                           (if (< (- orig-dist curr-dist) 1)
                                             (break))
                                           (/ (- orig-dist curr-dist) (+ 0.0001 (* 1.5 orig-dist))))))
                                   (if inverse
                                     (set factor (- 1 factor)))
                                   (var ar (band (brshift ((self :original-tile) which) 16) 0xFF))
                                   (var ag (band (brshift ((self :original-tile) which)  8) 0xFF))
                                   (var ab (band (brshift ((self :original-tile) which)  0) 0xFF))
                                   (var br (band (brshift color2 16) 0xFF))
                                   (var bg (band (brshift color2  8) 0xFF))
                                   (var bb (band (brshift color2  0) 0xFF))
                                   (def r (if (string/find "r" rgb?) (lerp ar br factor) ar))
                                   (def g (if (string/find "g" rgb?) (lerp ag bg factor) ag))
                                   (def b (if (string/find "b" rgb?) (lerp ab bb factor) ab))
                                   (put (self :tile) which (bor (blshift r 16) (blshift g 8) b)))
                :TRIG-create-emitter (fn [self ticks ctx emitter-template]
                                       (def new-emitter (deepclone emitter-template))
                                       (put new-emitter :initial (deepclone (self :coord)))
                                       (put new-emitter :target (deepclone ((self :parent) :target)))
                                       (put new-emitter :parent self)
                                       (array/push (ctx :emitters) new-emitter))
                :TRIG-set-explosion-expand-status (fn [self ticks ctx parent finished?]
                                                    (put (get-parent self parent) :explosion-finished-expanding finished?))
                :TRIG-die (fn [self &]
                            (put self :dead true))
                })
(defn new-particle [table] (table/setproto table Particle))

(def Emitter @{
               :particle (table/setproto @{} Particle)
               :lifetime nil                            # how many ticks before shutting down
               :spawn-count 1                           # number of particles to spawn each tick
               :spawn-delay 0                           # ticks to wait between spawns
               :triggers []
               :get-spawn-tile   (fn [self ticks ctx tile] tile)
               :get-spawn-params (fn [self ticks ctx coord target] [coord target])
               :get-spawn-speed  (fn [self ticks ctx speed] speed)
               :birth-delay 0                           # how many ticks to wait before activating

               # Context
               :delay-until-spawn 0
               :age 0
               :dead false
               :inactive false
               :parent nil
               :total-spawned 0
               :initial nil
               :target nil

               # Context specific to an effect
               :explosion-finished-expanding false

               :tick (fn [self ticks ctx]
                       (if (> (self :birth-delay) 0)
                         (do
                           (-- (self :birth-delay))
                           (break)))
                       (if (and (not (self :inactive))
                                (<= (self :delay-until-spawn) 0))
                         (do
                           (def spawn-count
                             (case (type (self :spawn-count))
                               :function (:spawn-count self ticks ctx)
                               :number (self :spawn-count)))
                           (for i 0 spawn-count
                             (do
                               (var new (deepclone (self :particle)))
                               (let [[coord target]
                                    (:get-spawn-params self ticks ctx (self :initial) (self :target))]
                                 (if (or (not coord) (not target))
                                   (break))
                                 # Just gonna vent my frustrations here: Janet,
                                 # why the FUCK do you have to do a
                                 # copy-by-pointer when assigning a new
                                 # variable to an existing table or array? I've
                                 # wasted at least two hours here trying to
                                 # figure out why a single particle updating
                                 # their position would magically move all
                                 # other particles as well (+ the particle
                                 # template in the emitter table).
                                 (put new :coord (deepclone coord)) # CLONE the damn coord
                                 (put new :initial-coord (deepclone coord)) # CLONE the damn coord
                                 (put new :target (deepclone target))) # CLONE the damn coord
                               (let [tile (:get-spawn-tile self ticks ctx (new :tile))]
                                 (put new :tile (deepclone tile))
                                 (put new :original-tile (deepclone tile)))
                               (put new :parent self)
                               (put new :speed (:get-spawn-speed self ticks ctx ((self :particle) :speed)))
                               (put new :id (+ (* (math/random) 100) (math/random)))
                               (array/push (ctx :particles) new)
                               (++ (self :total-spawned))))
                           (put self :delay-until-spawn (self :spawn-delay))))
                       (each trigger (self :triggers)
                         (if (((trigger 0) 0) self ticks ctx ;(slice (trigger 0) 1))
                           (((trigger 1) 0) self ticks ctx ;(slice (trigger 1) 1))))
                       (++ (self :age))
                       (-- (self :delay-until-spawn))
                       (> (self :age) (:get-lifetime self ticks ctx)))
               :get-lifetime (fn [self ticks ctx &]
                               (case (type (self :lifetime))
                                 :function (:lifetime self ticks ctx)
                                 :number (self :lifetime)))

               # :get-spawn-params presets
               :SPAR-sweeping-beams (fn [&]
                                      (fn [self ticks ctx coord target]
                                        (let [x (+ (((ctx :bounds) :start) :x) (% (self :total-spawned) ((ctx :bounds) :width)))]
                                          [(new-coord x (((ctx :bounds) :start) :y))
                                           (new-coord x (+ (((ctx :bounds) :start) :y) ((ctx :bounds) :height)))])))

               # :get-spawn-speed presets
               :SSPD-min-sin-ticks (fn [self ticks ctx speed]
                                     (max 0.1 (- speed (math/random) (math/abs (math/sin ticks)))))
               :SSPD-min-sin-ticks2 (fn [self ticks ctx speed]
                                      (max 0.1 (- speed (math/random) (math/abs (math/sin (rad (* 10 ticks)))))))

               # :spawn-count presets
               :SCNT-dist-to-target (fn [self &] (+ (:distance-euc ((self :particle) :coord) ((self :particle) :target)) 1))
               :SCNT-dist-to-target-360 (fn [self &] (* 360 (+ 1 (:distance ((self :particle) :coord) ((self :particle) :target)))))

               :COND-age-eq? (fn [self ticks ctx num]
                               (= (self :age) num))

               :TRIG-inactivate (fn [self ticks ctx]
                                  (put self :inactive true))
               })
(defn new-emitter [table] (table/setproto table Emitter))
(defn new-emitter-from [table proto] (table/setproto table (table/proto-flatten proto)))
(defmacro SPAR-circle [&named inverse radius sparsity-factor]
  (default inverse false)
  (default radius :distance)
  (default sparsity-factor 3)
  ~(fn [self ticks ctx coord target]
    (let [lrad (case ,radius :distance (+ 1 (:distance coord target)) ,radius)
          angle (rad (* ,sparsity-factor (/ (self :total-spawned) lrad)))
          n (+ (% (self :total-spawned) lrad) 0)]
      (if ,inverse
        [(:move-angle target n angle) target]
        [(:move-angle coord n angle) target]))))
(defmacro SPAR-explosion [&named distance inverse which-origin sparsity-factor]
  (default distance :distance-to-target)
  (default inverse false)
  (default sparsity-factor 2)
  (default which-origin :coord)
  ~(fn [self ticks ctx p-coord target]
    (let [origin (case ,which-origin :coord p-coord :target target)
          angle  (* (/ (% (* ,sparsity-factor (self :total-spawned)) 360) 180) math/pi)
          dist   (case ,distance
                   :distance-to-target (:distance origin target)
                   ,distance)
          ntarg  (:move-angle origin dist angle)]
      (if ,inverse [ntarg origin] [origin ntarg]))))

(def Context @{
               :target (new-coord)
               :bounds (new-rect)
               :particles @[]
               :emitters @[]
               :initial (new-coord)
               })
(defn new-context [initial target area-size emitters]
  (table/setproto @{ :initial initial :bounds area-size :target target :emitters emitters} Context))

(defn template-chargeover [chars color1 color2 &named direction speed lifetime which maxdist mindist style stopshort]
  (default direction                          :out)
  (default speed                              0.25)
  (default lifetime                              9)
  (default which                           :target)
  (default maxdist                               4)
  (default mindist (case direction :out 1 :in 2.5))
  (default style                               :bg)
  (default stopshort                         false)
  (def special-triggers
    (case style
      :bg   @[ [[:COND-true] [:TRIG-lerp-color :bg color2 "rgb" @(:completed-journey)]] ]
      :nobg @[]))
  (def tile
    (case style
      :bg   (new-tile @{ :ch "_" :fg color2 :bg color1 })
      :nobg (new-tile @{ :ch "_" :fg color1 :bg-mix 0.6 })))
  (new-emitter @{
      :particle (new-particle @{
        :tile tile
        :speed speed
        :triggers (array/concat special-triggers @[
          [[:COND-percent? 40] [:TRIG-scramble-glyph chars]]
          [[:COND-true] [:TRIG-lerp-color :fg color2 "rgb" @(:completed-journey)]]
        ])
      })
      :lifetime lifetime
      :spawn-count 7
      :get-spawn-params (fn [self ticks ctx origin target]
                          (let [angle  (/ (* (math/random) 360 math/pi) 180)
                                dist1  (+ mindist (* (math/random) (- maxdist mindist)))
                                dist2  (+ mindist (* (math/random) (- maxdist mindist)))
                                coord  (case which :target target :origin origin)
                                noncoord (case which :target origin :origin target)]
                            (case direction
                              :out [coord (:move-angle coord dist1 angle)]
                              :in  [(:move-angle coord dist2 angle) (:move-angle coord 1 angle)])))
    }))

(defn template-lingering-zap [chars bg fg lifetime &named bg-mix territorial lerp-to require-nonwall require-los]
  (default bg-mix 0.7)
  (default territorial false)
  (default lerp-to nil)
  (default require-nonwall true)
  (default require-los 1)
  (def color-change-trigger (case lerp-to
    nil [[:COND-true] [:TRIG-modify-color :bg "rgb" [:completed-lifetime 1.3]]]
        [[:COND-true] [:TRIG-lerp-color :bg lerp-to "rgb" [:completed-lifetime 1.3] :inverse true]]))

  (new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "Z" :fg fg :bg bg :bg-mix bg-mix })
      :speed 0 :lifetime lifetime :territorial territorial
      :require-nonwall require-nonwall :require-los require-los
      :triggers @[
        [[:COND-true] [:TRIG-scramble-glyph chars]]
        color-change-trigger
      ]
    })
    :lifetime 0
    :spawn-count (Emitter :SCNT-dist-to-target)
    :get-spawn-params (fn [self ticks ctx coord target]
                        (let [angle (:angle target coord)
                              n (% (self :total-spawned) (+ 1 (:distance-euc coord target)))]
                          [(:move-angle coord n angle) target]))
   }))

(defn template-hellfire-explosion [&named distance lifetime]
  (default lifetime 0)
  (default distance 1)
  (def spf (case distance
             1 45
             2 20
             (assert false)))
  (def spc (case distance
             1 12
             2 24
             (assert false)))
  (new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "Z" :fg 0xcc3422 :bg 0x882011 :bg-mix 0.8 })
      :speed 0.8
      :lifetime 12
      :triggers @[
        [[:COND-true] [:TRIG-scramble-glyph ASCII_CHARS]]
        [[:COND-true] [:TRIG-lerp-color :fg 0xddcc22 "rgb" [:sine-custom
                        (fn [self ticks &] (* 16 (+ ticks (* (math/random) 20))))]]]
      ]
    })
    :lifetime lifetime
    :spawn-count spc
    :get-spawn-params (SPAR-explosion :which-origin :target :distance distance :sparsity-factor spf)
  })
)

(defn template-explosion [&named embers? die-out? speed-variation-preset color1 color2]
  (default embers?              true)
  (default die-out?             true)
  (default color1           0xffff00)
  (default color2           0x851e00)
  (default speed-variation-preset :1)
  (new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch " " :fg 0 :bg color1 :bg-mix 0.8 })
      :speed 2
      :triggers @[
        [[:COND-reached-target? true] [:TRIG-set-explosion-expand-status 1 true]]

        [
         [:COND-explosion-still-expanding? 1] [:COND-percent? 30]
         [:TRIG-modify-color :bg "g" [:random-factor 0.70 0.72]]
        ]
        [[:COND-explosion-still-expanding? 1] [:TRIG-reset-original-tile]]

        (if die-out?
          [[:COND-explosion-done-expanding? 1] [:TRIG-reset-lifetime-once 3 0]]
          nil)
        #[[:COND-explosion-done-expanding? 1] [:TRIG-set-speed 0]]

        (if die-out?
          [[:COND-explosion-done-expanding? 1] [:TRIG-lerp-color :bg color2 "rgb" [:completed-lifetime 0.8] :inverse true]]
          [[:COND-explosion-done-expanding? 1] [:TRIG-lerp-color :bg color2 "rgb" [:completed-journey]]])

        (if embers?
          [[:COND-explosion-done-expanding? 1] [:COND-percent? 1] [:TRIG-create-emitter (new-emitter @{
            :particle (new-particle @{
              :tile (new-tile @{ :ch " " :fg 0 :bg 0xffff00 :bg-mix 0.8 })
              # XXX: For some reason janet crashes (illegal instruction) when lifetime == 5 or lifetime == 7
              :lifetime 3
              :speed 0
              :triggers @[ [[:COND-true] [:TRIG-lerp-color :bg 0x851e00 "rgb" [:completed-lifetime 2]]] ]
            })
            :lifetime 1
          })]]
          nil)
      ]
    })
    :lifetime 2
    :spawn-count 180
    :get-spawn-params (SPAR-explosion)
    :get-spawn-speed (case speed-variation-preset
                       :1 (Emitter :SSPD-min-sin-ticks)
                       :2 (Emitter :SSPD-min-sin-ticks2))
  }))

(defn template-lerp-single [color1 color2 &named lifetime which]
  (default lifetime 4)
  (default which :target)
  (new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch " " :bg color1 :bg-mix 0.9 })
      :speed 0    :lifetime lifetime
      :triggers @[
        [[:COND-true] [:TRIG-lerp-color :bg color2 "rgb" [:completed-lifetime 1] :inverse true]]
      ]
    })
    :lifetime 1
    :get-spawn-params (fn [self ticks ctx coord target]
                        (case which
                          :target [target coord]
                          :origin [coord target]))
  }))

(defn _statue-border-effect [color linedraw direction]
  (new-emitter @{
    :particle (new-particle @{ :tile (new-tile @{ :ch linedraw :fg color }) :speed 0 :lifetime 1 })
    :lifetime 1
    :get-spawn-params (fn [self ticks ctx coord target] [(:move coord direction) target])
  }))

(defn _beams-single-emitter [func]
  (new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "O" :fg 0xffffff :bg 0xffffff :bg-mix 1 })
      # require-los not originally set, set to nerf particle spawns
      :speed 0 :lifetime 1 :require-los 1 :require-nonwall 0
      :triggers @[
        [[:COND-true]
          [:TRIG-lerp-color :bg 0x77776f "rgb"
            [:sine-custom (fn [self ticks &] (* (:distance (((self :parent) :particle) :target) (self :coord)) 3 ticks))]]]
        [[:COND-true] [:TRIG-scramble-glyph ".,;:'~*-=_+"]]
      ]
    })
    :lifetime 11
    # nerfed to ×1 from ×2 due to particle engine being really slow
    :spawn-count (fn [self ticks ctx] (* (max ((ctx :bounds) :width) ((ctx :bounds) :height)) 1)) 
    :get-spawn-params (fn [self ticks ctx coord target]
                        (let [dist  (max ((ctx :bounds) :width) ((ctx :bounds) :height))
                              angle (rad (func (* 8 (/ (self :total-spawned) dist))))
                              n     (+ (% (self :total-spawned) dist) 1)]
                          [(:move-angle coord n angle) target]))
  }))

# TODO: fade in 1st 5-10 ticks, then fade out last 5-10 ticks
(defn _beams-golden-blue [func]
  (new-emitter @{
        :particle (new-particle @{
          :tile (new-tile @{ :ch "." :fg 0x220700 :bg 0xffd700 :bg-mix 1.0 })
          :speed 0.3 :lifetime 50 :require-los 0 :require-nonwall 0
          :triggers @[
            [[:COND-custom (fn [_s ticks &] (<= ticks 10))]
              [:TRIG-modify-color :bg "a" [:custom :origtile (fn [_s ticks &] (* 0.1 ticks))]]]
            [[:COND-custom (fn [_s ticks &] (>= ticks 45))]
              [:TRIG-modify-color :bg "a" [:custom :origtile (fn [_s ticks &] (- 1 (* 0.03 (- ticks 45))))]]]
            [[:COND-percent? 5] [:TRIG-scramble-glyph "`-=!#$%^&*()_+[]\\{}|;':\",./<>?"]]
            [[:COND-true]
              [:TRIG-lerp-color :bg 0x0000ff "rgb" #0x77776f "rgb"
                [:sine-custom (fn [self ticks &] (* (:distance (((self :parent) :particle) :target) (self :coord)) 1.5 ticks))]]]
          ]
        })
        :lifetime 21
        :spawn-count (fn [self ticks ctx] (* (max ((ctx :bounds) :width) ((ctx :bounds) :height)) 2)) 
        :get-spawn-params (fn [self ticks ctx coord target]
                            (let [dist  (max ((ctx :bounds) :width) ((ctx :bounds) :height))
                                  angle (rad (func (* 4 (/ (self :total-spawned) dist))))
                                  n     (+ (% (self :total-spawned) dist) 1)]
                              [(:move-angle coord n angle) target]))
      }))

(def emitters-table @{
  "test" @[]
  "null" @[]
  "lzap-electric" @[ (template-lingering-zap "AEFHIKLMNTYZ13457*-=+~?!@#%&" 0x9fefff 0x7fc7ef 7) ]
  "lzap-golden" @[ (template-lingering-zap ".#.#.#." LIGHT_GOLD GOLD 12) ]
  "lzap-green" @[ (template-lingering-zap ROUND_CHARS GREEN LIGHT_GREEN 7) ]
  "lzap-green-concrete" @[ (template-lingering-zap ".#%," CONCRETE LIGHT_GREEN 4) ]
  "explosion-simple" @[ (template-explosion) ]
  "explosion-fire1" @[ (template-explosion :embers? false :die-out? false :speed-variation-preset :2 :color1 0xff9f00) ]
  "lzap-fire-quick" @[ (template-lingering-zap " " 0x770f0f 0 4) ]
  "zap-electric" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "Z" :fg 0x9fefff :bg 0x7fc7ef :bg-mix 0.7 })
      :speed 1
      :triggers @[
        [[:COND-true] [:TRIG-scramble-glyph "AEFHIJKLMNTYZ12357*-=+~?!@#%&"]]
        [[:COND-true] [:TRIG-modify-color :bg "rgb" @(:completed-parent-lifetime 1 4.5)]]
      ]
    })
    :lifetime 5
    :spawn-count (Emitter :SCNT-dist-to-target)
   })]
  "zap-bolt-fiery" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "+" :fg 0x9b3434 :bg-mix 1 })
      :speed 0.9
      :triggers @[
        [[:COND-true] [:TRIG-set-glyph [:overall-cardinal-angle ["|" "|" "-" "-"]]]]
        [[:COND-true] [:TRIG-create-emitter (new-emitter @{
          :particle (new-particle @{
            :tile (new-tile @{ :ch " " :fg 0 :bg 0xcc5233 :bg-mix 0.7 })
            :speed 0
            :triggers @[
              [[:COND-true] [:TRIG-reset-lifetime-once (fn [&] (random-choose [5 5 5 6])) 0]]
              [[:COND-true] [:TRIG-modify-color :bg "a" [:completed-lifetime 0.9]]]
            ]
          })
          :lifetime 0
        })]]
      ]
    })
    :lifetime 0
   })]
  "zap-bolt" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "+" :fg 0x7c5353 :bg-mix 1 })
      :speed 0.9
      :triggers @[
        [[:COND-true] [:TRIG-set-glyph [:overall-cardinal-angle ["|" "|" "-" "-"]]]]
      ]
    })
    :lifetime 0
   })]
  "zap-awaken-construct" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "Z" :fg 0x9fefff :bg-mix 1 })
      :speed 1
      :triggers @[ [[:COND-true] [:TRIG-scramble-glyph "[]{}()*-=+~?!@#%&"]] ]
    })
    :lifetime 3
    :spawn-count (Emitter :SCNT-dist-to-target)
   })]
  "zap-sword" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "|" :fg 0xef9fff :bg 0 :bg-mix 1 })
      :require-los 0
      :triggers @[
        [[:COND-nth-tick 1] [:TRIG-cycle-glyph "|/-\\"]]
        # Smooth-end transformation. i.e. 1-((1-x)^2)
        [[:COND-true] [:TRIG-set-speed (fn [self &] (+ 0.1 (- 1 (math/pow (:completed-journey self) 2))))]]
        [[:COND-true] [:TRIG-create-emitter (new-emitter @{
          :particle (new-particle @{
            :tile (new-tile @{ :ch " " :fg 0 :bg 0x442266 :bg-mix 1 })
            :speed 0.1 :require-nonwall 0 :require-los 0
            :triggers @[
              [[:COND-reached-target? true] [:TRIG-set-speed 0]]
              [[:COND-true] [:TRIG-reset-lifetime-once (fn [&] (random-choose [9 5])) 0]]
              [[:COND-true] [:TRIG-modify-color :bg "rg" [:completed-lifetime 1]]]
            ]
          })
          :lifetime 2
          :birth-delay 2
          :get-spawn-params (fn [self ticks ctx coord target]
                              (let [nangle (+ (:angle target coord) (random-choose [(rad 90) (rad -90) 0 0 0]))
                                    ntarg  (:move-angle coord 1 nangle)]
                                [ntarg coord]))
        })]]
      ]
    })
    :lifetime 0
   })]
  "zap-fire-messy" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch " " })
      :speed 1.7
      :triggers @[
        [[:COND-reached-target? true] [:TRIG-set-explosion-expand-status 1 true]]
        [[:COND-percent? 100] [:TRIG-create-emitter (new-emitter @{
          :particle (new-particle @{
            :tile (new-tile @{ :ch " " :fg 0 :bg 0xff9900 :bg-mix 0.9 })
            :speed 0
            :triggers @[
              [[:COND-true] [:TRIG-reset-lifetime-once (fn [&] (random-choose [6 8 10])) 0]]
              [[:COND-true] [:TRIG-modify-color :bg "a" [:completed-lifetime 0.9]]]
              [[:COND-explosion-still-expanding? 3] [:COND-percent? 5]
               [:TRIG-custom (fn [self &]
                               (put self :lifetime (+ (self :lifetime) 3))
                               (put (self :tile) :bg-mix 0.9))]
              ]
            ]
          })
          :lifetime 1
        })]]
        [[:COND-percent? 60] [:TRIG-create-emitter (new-emitter @{
          :particle (new-particle @{
            :tile (new-tile @{ :ch " " :fg 0 :bg 0xff9900 :bg-mix 0.4 })
            :speed 0.7
            :triggers @[
              [[:COND-reached-target? true] [:TRIG-set-speed 0]]
              [[:COND-true] [:TRIG-reset-lifetime-once (fn [&] (random-choose [2 5])) 0]]
              [[:COND-true] [:TRIG-modify-color :bg "a" [:completed-lifetime 0.95]]]
            ]
          })
          :lifetime 1
          :birth-delay 1
          :get-spawn-params (fn [self ticks ctx coord target]
                              (let [nangle (+ (:angle target coord) (random-choose [(rad 90) (rad -90)]))
                                    ntarg  (:move-angle coord 1 nangle)]
                                [coord ntarg]))

       })]]
      ]
    })
    :spawn-count 2
    :lifetime 0
    :get-spawn-speed (Emitter :SSPD-min-sin-ticks)
   })]
  "zap-speeding-bolt" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch " " :fg GREEN :bg LIGHT_GREEN :bg-mix 0.6 })
      :speed 1.2
      :triggers @[
        [[:COND-true] [:TRIG-set-glyph [:overall-cardinal-angle ["╿" "╽" "╾" "╼"]]]]
        [[:COND-true] [:TRIG-create-emitter (new-emitter @{
          :particle (new-particle @{
            :tile (new-tile @{ :ch "0" :fg GREEN :bg GREEN :bg-mix 0.5 })
            :speed 0
            :lifetime 6
            :triggers @[
              [[:COND-true] [:TRIG-scramble-glyph "L1!@#$%^*|\\][-+_"]]
              [[:COND-true] [:TRIG-modify-color :bg "a" [:completed-lifetime 0.5]]]
              [[:COND-parent-dead? 2] [:TRIG-modify-color :fg "rgb" [:fixed-factor 0.8]]]
            ]
          })
          :lifetime 0
        })]]
      ]
    })
    :lifetime 0
   })]
  "zap-fire-trails" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch " " })
      :speed 1
      :triggers @[
        [[:COND-true] [:TRIG-create-emitter (new-emitter @{
          :particle (new-particle @{
            :tile (new-tile @{ :ch "0" :fg 0xff9900 :bg 0xff9900 :bg-mix 1 })
            :speed 0
            :lifetime 10
            :triggers @[
              [[:COND-true] [:TRIG-scramble-glyph "!@#$%^&*(){}|\\][=-+_1234567890"]]
              [[:COND-true] [:TRIG-modify-color :bg "a" [:completed-lifetime 0.5]]]
              [[:COND-parent-dead? 2] [:TRIG-modify-color :fg "rgb" [:fixed-factor 0.8]]]
            ]
          })
          :lifetime 0
        })]]
      ]
    })
    :lifetime 0
   })]
  "zap-statues" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "*" :fg LIGHT_GOLD })
        :speed 2
        :triggers @[
          [[:COND-true]                  [:TRIG-lerp-color :fg 0x5f99ff "rgb" [:completed-journey]]]
          [[:COND-reached-target? false] [:COND-percent? 90] [:TRIG-set-glyph [:overall-cardinal-angle ["│" "│" "─" "─"]]]]
          [[:COND-reached-target? false] [:COND-percent? 10] [:TRIG-scramble-glyph "*+~"]]
          [[:COND-reached-target?  true] [:TRIG-scramble-glyph "$#%&OGBQUDJ08963@?"]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "╭" :nw)]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "─" :n)]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "╮" :ne)]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "│" :e)]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "│" :w)]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "╰" :sw)]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "─" :s)]]
          [[:COND-reached-target?  true] [:TRIG-create-emitter (_statue-border-effect 0x5f99ff "╯" :se)]]
          [[:COND-parent-dead? 1] [:TRIG-die]]
        ]
      })
      :lifetime (fn [self &] (+ 5 (:distance ((self :particle) :coord)  ((self :particle) :target))))
      :spawn-count (Emitter :SCNT-dist-to-target)
      :get-spawn-speed (Emitter :SSPD-min-sin-ticks)
    })]
  "zap-electric-charging" @[
    # TODO: 0x495356 was taken from a Cogmind animation, and mayyybe doesn't go
    #       too well with ELEC_BLUE*. Need to check on this after I've cleared
    #       my brain -- after hours of staring at the same animation the colors
    #       look to be the exact same hue.
    (template-chargeover ASCII_CHARS ELEC_BLUE2 0x495355 :which :origin :speed 0.3 :lifetime 8 :maxdist 2)
    (new-emitter-from @{ :birth-delay 8 } (template-lingering-zap ASCII_CHARS ELEC_BLUE1 ELEC_BLUE2 9 :bg-mix 0.4))
  ]
  "zap-conjuration" @[
    (template-chargeover ASCII_CHARS 0x0a0a90 0x661188 :which :origin :speed 0.3 :lifetime 8 :maxdist 2)
    (new-emitter-from @{ :birth-delay 8 }
      (template-lingering-zap ASCII_CHARS 0x0a0a90 0x661188 9 :bg-mix 0.8 :require-nonwall false :require-los 0))
  ]
  "zap-pull-foe" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "×" })
        :speed 1
        :triggers @[
          [[:COND-reached-target? false] [:TRIG-create-emitter (new-emitter @{
            :particle (new-particle @{
                                      :tile (new-tile @{ :ch "×" :fg 0x777777 :bg-mix 0 })
                                      :lifetime 10
                                      :speed 0
                                      })
            :lifetime 0
          })]]
          [[:COND-reached-target? true] [:TRIG-create-emitter (new-emitter @{
            :particle (new-particle @{
              :tile (new-tile @{ :ch "@" :fg 0x9f8f74 })
              :speed 1
              :triggers @[
                [[:COND-reached-target? true] [:TRIG-die]]
                [[:COND-true] [:TRIG-create-emitter (new-emitter @{
                  :particle (new-particle @{
                    :tile (new-tile @{ :ch "@" :fg 0xaaaaaa :bg-mix 0 })
                    :speed 0 :territorial true
                    :triggers @[[[:COND-parent-dead? 2] [:TRIG-die]]]
                  })
                  :lifetime 0
                })]]
              ]
            })
            :lifetime 0
            :get-spawn-params (fn [self ticks ctx _ target]
                                [target ((get-parent self 1) :initial-coord)])
          })]]
        ]
      })
      :lifetime 0
     })
  ]
  "zap-resist-divine-wrath" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "X" :fg 0xcc0000 :bg 0x880000 :bg-mix 0.8 })
        :speed 1.8
        :triggers @[
          [[:COND-percent? 40] [:TRIG-scramble-glyph POINT_CHARS]]
          [[:COND-reached-target? true]
           [:TRIG-create-emitter
            (template-chargeover POINT_CHARS 0x660000 0xcc0000 :direction :in :speed 0.7 :lifetime 5 :mindist 1 :maxdist 3)
            ]
          ]
        ]
      })
      :lifetime 2
      :spawn-count 1
    })
  ]
  "zap-hellfire" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "Z" :fg 0xcc3422 :bg 0x882011 :bg-mix 0.8 })
        :speed 2
        :triggers @[
          [[:COND-true] [:TRIG-scramble-glyph ASCII_CHARS]]
          [[:COND-reached-target? true]
           [:TRIG-create-emitter (template-hellfire-explosion :distance 1)]
          ]
          [[:COND-parent-dead? 1] [:TRIG-die]]
        ]
      })
      :lifetime (fn [self &] (+ 7 (:distance ((self :particle) :coord)  ((self :particle) :target))))
      :spawn-count (Emitter :SCNT-dist-to-target)
      :get-spawn-speed (Emitter :SSPD-min-sin-ticks)
    })
  ]
  "zap-hellfire-electric" @[
    (template-lingering-zap ASCII_CHARS 0 0xcc3422 5 :bg-mix 0.0 :require-nonwall false)
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "Z" :fg 0xcc3422 :bg 0 :bg-mix 0 })
        :speed 0.3
        :lifetime 2
        :triggers @[
          [[:COND-true] [:TRIG-scramble-glyph ASCII_CHARS]]
          [[:COND-true] [:TRIG-lerp-color :fg 0xddcc22 "rgb" [:sine-custom
                          (fn [self ticks &] (* 8 (+ ticks (* (math/random) 20))))]]]
        ]
      })
      :lifetime 5
      :spawn-count 50
      :get-spawn-params (SPAR-explosion :which-origin :target :distance 1 :sparsity-factor 20)
    })
  ]
  "zap-mass-insanity" @[
    (template-lingering-zap ASCII_CHARS 0 0xaa55cc 4 :bg-mix 0.0 :require-nonwall false :require-los 0)
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "Z" :fg 0xaa55cc :bg 0 :bg-mix 0 })
        :speed 1
        :triggers @[
          [[:COND-true] [:TRIG-scramble-glyph ASCII_CHARS]]
          [[:COND-true] [:TRIG-lerp-color :fg 0x0a0a90 "rgb" @(:completed-journey)]]
        ]
      })
      :lifetime 1
      :spawn-count 180
      :get-spawn-params (SPAR-explosion :which-origin :target :distance 3 :sparsity-factor 4)
    })
  ]
  # Essentially the same as zap-mass-insanity, but with TRIG-set-glyph(overall-cardinal-angle) and
  # different colors (which match the amnesia beams effect somewhat)
  "zap-mass-amnesia" @[
    (template-lingering-zap ASCII_CHARS 0 0x5f6600 4 :bg-mix 0.0 :require-nonwall false :require-los 0)
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "Z" :fg 0xaa55cc :bg 0 :bg-mix 0 })
        :speed 1
        :triggers @[
          [[:COND-true] [:TRIG-scramble-glyph "*&~@+=<>:;"]]
          [[:COND-true] [:COND-percent? 60] [:TRIG-set-glyph [:overall-cardinal-angle ["│" "│" "─" "─"]]]]
          [[:COND-true] [:TRIG-lerp-color :fg 0x5f6600 "rgb" @(:completed-journey)]]
        ]
      })
      :lifetime (fn [self &] 3)
      :spawn-count (fn [self &] (* 3 45))
      :get-spawn-params (SPAR-explosion :which-origin :target :distance 2 :sparsity-factor 8)
    })
  ]
  "zap-crystal-chargeover" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch " " })
        :speed 0
        :lifetime 0
        :triggers @[
          [[:COND-true] [:TRIG-create-emitter (new-emitter @{
            :particle (new-particle @{
              :tile (new-tile @{ :ch "Z" :fg 0x5f6600 :bg 0xd7ff00 :bg-mix 0.5 })
              :speed 0.3
              :triggers @[
                [[:COND-percent? 40] [:TRIG-scramble-glyph SYMB1_CHARS]]
                [[:COND-true] [:TRIG-modify-color :bg "a" [:completed-journey] :inverse true]]
                [[:COND-reached-target? true] [:TRIG-set-speed 0]]
                [[:COND-reached-target? true] [:TRIG-reset-lifetime-once 5 0]]
                [[:COND-reached-target? true] [:TRIG-modify-color :bg "a" [:fixed-factor 1.3]]]
                [[:COND-reached-target? true] [:TRIG-scramble-glyph " "]]
              ]
            })
            :lifetime 7
            :spawn-count (fn [&] 5)
            :get-spawn-params (fn [self ticks ctx coord target]
                                (let [angle  (rad (* (math/random) 360))
                                      dist   (max 1 (* (math/random) 4))]
                                  [(:move-angle coord dist angle) coord]))
          })]]
        ]
      })
      :lifetime 0
      :spawn-count (Emitter :SCNT-dist-to-target)
      :get-spawn-params (fn [self ticks ctx coord target]
                          (let [angle (:angle target coord)
                                n (+ (% (self :total-spawned) (:distance coord target)) 1)]
                            [(:move-angle coord n angle) target]))
    })
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch " " :fg 0xd7ff00 :bg-mix 0 })
        :speed 1.2
        :triggers @[ [[:COND-true] [:TRIG-set-glyph [:overall-cardinal-angle ["╿" "╽" "╾" "╼"]]]] ]
      })
      :birth-delay 22
      :spawn-delay 3
      :lifetime (fn [self &] (+ 3 (:distance ((self :particle) :coord) ((self :particle) :target))))
      :spawn-count (Emitter :SCNT-dist-to-target)
    })
  ]
  "spawn-emberlings" @[
    (template-lingering-zap " " 0xff8800 0 1 :bg-mix 0.5)
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch " " :bg 0xff8800 :bg-mix 0.9 })
        :speed 0    :lifetime 10   :territorial true
        :triggers @[ [[:COND-true] [:TRIG-modify-color :bg "rgb" [:fixed-factor 0.8]]] ]
      })
      :lifetime 1
      :spawn-count (Emitter :SCNT-dist-to-target-360)
      :get-spawn-params (SPAR-circle :inverse true :radius 2)
    })
  ]
  "spawn-sparklings" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "Z" :fg ELEC_BLUE1 :bg ELEC_BLUE2 :bg-mix 0.2 })
        :speed 0 :lifetime 7
        :triggers @[
          [[:COND-percent? 40] [:TRIG-scramble-glyph ASCII_CHARS]]
          [[:COND-true] [:TRIG-lerp-color :fg 0x495355 "rgb" @(:completed-journey)]]
          [[:COND-parent-dead? 1] [:TRIG-set-speed 0.1]]
        ]
      })
      :lifetime 3
      :spawn-count (fn [&] 5)
      :get-spawn-params (fn [self ticks ctx coord target]
                          (let [angle  (% (* 3 (self :total-spawned)) 360)
                                ntarg  (:move-angle target 2 angle)]
                            [ntarg target]))
    })
  ]
  # Lots of stuff stolen from zap-fire-trails, and zap-sword
  "zap-disintegrate" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch " " :bg 0xd7d722 :bg-mix 0.7 })
        :require-los 0 :require-nonwall false
        :triggers @[
          [[:COND-true] [:TRIG-set-speed (fn [self &] (+ 0.5 (math/pow (:completed-journey self 0.7) 2)))]]
          [[:COND-true] [:TRIG-create-emitter (new-emitter @{
            :particle (new-particle @{
              :tile (new-tile @{ :ch "0" :fg 0xd7d722 :bg DARK_GOLD :bg-mix 1 })
              :require-los 0 :require-nonwall false
              :speed 0
              :lifetime 15
              :triggers @[
                [[:COND-true] [:TRIG-scramble-glyph "!@#$%^&*(){}|\\][=-+_1234567890"]]
                [[:COND-true] [:TRIG-modify-color :bg "a" [:completed-lifetime 0.5]]]
                [[:COND-parent-dead? 2] [:TRIG-modify-color :fg "rgb" [:fixed-factor 0.8]]]
              ]
            })
            :lifetime 0
          })]]
        ]
      })
      :lifetime 0
      :spawn-count (Emitter :SCNT-dist-to-target)
     })
  ]
  "zap-iron-inacc" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "+" :fg 0xccccdd :bg 0 :bg-mix 0 })
        :speed 0.6
        :triggers @[
          [[:COND-percent? 30] [:TRIG-scramble-glyph "*-=+~?!@#%&"]]
        ]
      })
      :lifetime 5
      :spawn-delay 1
      :spawn-count (fn [&] 3)
      :get-spawn-params (fn [self ticks ctx coord target]
                          (let [first? (= (self :total-spawned) 0)
                                diffx (- (target :x) (coord :x))
                                diffy (- (target :y) (coord :y))
                                angle (- (math/atan2 diffy diffx) (if first? 0 (* 0.25 (random-choose [-1 0 1]))))
                                dist  (- (:distance coord target) (if first? 0 (* (+ 0.5 (math/random)) 2.5)))
                                ntarg  (new-coord (+ (coord :x) (* dist (math/cos angle)))
                                                  (+ (coord :y) (* dist (math/sin angle))))]
                            [coord ntarg]))
    })
  ]
  "explosion-hellfire" @[
    (template-hellfire-explosion :distance 2 :lifetime 5)
  ]
  "explosion-electric-sparkly" @[(new-emitter @{
    :particle (new-particle @{
      :tile (new-tile @{ :ch "·" :fg 0x00e9e9 :bg 0 :bg-mix 0 })
      :speed 2
      :lifetime 10
      :triggers @[
        [[:COND-reached-target? true] [:TRIG-set-explosion-expand-status 1 true]]
        [[:COND-explosion-done-expanding? 1] [:TRIG-reset-lifetime-once (fn [&] (+ 7 (* (math/random) 15))) 0]]

        [[:COND-percent? 0.5] [:TRIG-create-emitter (new-emitter @{
          :particle (new-particle @{
            :tile (new-tile @{ :ch "·" :fg 0x00ffff :bg 0x007f7f :bg-mix 0.8 })
            :speed 0
            :lifetime 5
            :triggers @[
              [[:COND-explosion-done-expanding? 1] [:TRIG-lerp-color :bg 0x001212 "rgb" [:completed-lifetime]]]
            ]
          })
          :lifetime 1
        })]]
      ]
    })
    :lifetime (fn [self &] (* 2 (:distance ((self :particle) :coord)  ((self :particle) :target))))
    :spawn-count (fn [self &] 120)
    :get-spawn-params (SPAR-explosion :inverse true :sparsity-factor 6)
    :get-spawn-speed (Emitter :SSPD-min-sin-ticks)
  })]
  "explosion-bluegold" @[
    (new-emitter @{
            :particle (new-particle @{
              :tile (new-tile @{ :ch "Z" :fg GOLD :bg LIGHT_GOLD :bg-mix 0.5 })
              :speed 0.4
              :triggers @[
                [[:COND-percent?  5] [:TRIG-custom (fn [self &]
                                                     (put (self :tile) :bg 0x3333ff) (put (self :tile) :fg 0)
                                                     (put (self :original-tile) :bg 0x3333ff) (put (self :original-tile) :fg 0))]]
                [[:COND-percent? 60] [:TRIG-scramble-glyph SYMB1_CHARS]]
                [[:TRIG-modify-color :bg "a" [:completed-journey] :inverse true]]
                [[:COND-reached-target?  true] [:TRIG-die]]
              ]
            })
            :lifetime 8
            :spawn-count (fn [&] 12)
            :get-spawn-params (fn [self ticks ctx coord target]
                                (let [angle  (rad (* (math/random) 360))
                                      dist   (max 1 (* (math/random) 12))]
                                  [(:move-angle coord dist angle) coord]))
          })
  ]
  "explosion-green" @[
    (new-emitter @{
            :particle (new-particle @{
              :tile (new-tile @{ :ch "O" :fg GREEN :bg LIGHT_GREEN :bg-mix 0.8 })
              :speed 0.7
              :triggers @[
                [[:COND-percent?  7] [:TRIG-custom (fn [self &]
                                        (put (self :tile) :bg 0x0a0a90)
                                        (put (self :tile) :fg 0xaa55cc)
                                        (put (self :original-tile) :bg 0x0a0a90)
                                        (put (self :original-tile) :fg 0xaa55cc))]]
                [[:COND-percent? 50] [:TRIG-scramble-glyph ROUND_CHARS]]
                [[:TRIG-modify-color :bg "a" [:completed-journey]]]
                [[:COND-reached-target?  true] [:TRIG-die]]
              ]
            })
            :lifetime 3
            :spawn-count 24
            :get-spawn-params (fn [self ticks ctx coord target]
                                (let [mdist  (:distance coord target)
                                      angle  (rad (* (math/random) 360))
                                      dist   (max (* mdist 0.8) (* (math/random) mdist))]
                                  [coord (:move-angle coord dist angle)]))
          })
  ]
  "beams-call-undead" @[
    (_beams-single-emitter (fn [deg] (+ 180 deg)))
    (_beams-single-emitter (fn [deg] (- 180 deg)))
    (_beams-single-emitter (fn [deg] (+ 360 deg)))
    (_beams-single-emitter (fn [deg] (- 360 deg)))
  ]
  "beams-candle-extinguish" @[
    (_beams-golden-blue (fn [deg] (+ 180 deg)))
    (_beams-golden-blue (fn [deg] (- 180 deg)))
    (_beams-golden-blue (fn [deg] (+ 360 deg)))
    (_beams-golden-blue (fn [deg] (- 360 deg)))
  ]
  "pulse-brief" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch ":" :fg 0x888888 :bg BG :bg-mix 0.9 })
        :speed 0    :lifetime 12   :territorial true   :require-los 1
        :triggers @[
          [[:COND-true] [:TRIG-lerp-color :bg 0xffffff "rgb" [:sine-custom (fn [self ticks &] (* 16 ticks))]]]
        ]
      })
      :lifetime 0
      :spawn-count (Emitter :SCNT-dist-to-target-360)
      :get-spawn-params (SPAR-circle)
    })
  ]
  "pulse-twice-electric-explosion" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch ":" :fg ELEC_BLUE1 :bg 0x2f2f33 :bg-mix 0.9 })
        :speed 0    :lifetime 45   :territorial true
        :triggers @[ [[:COND-true] [:TRIG-lerp-color :bg ELEC_BLUE2 "rgb" [:sine-custom (fn [self ticks &] (* 8.2 ticks))]]] ]
      })
      :lifetime 0
      :spawn-count (Emitter :SCNT-dist-to-target-360)
      :get-spawn-params (SPAR-circle :inverse true :radius 2)
    })
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch ":" :fg ELEC_BLUE1 :bg ELEC_BLUE2 :bg-mix 1 })
        :speed 0    :lifetime 12   :territorial true
        :triggers @[
          [[:COND-true] [:TRIG-scramble-glyph "~!@#$%^&*()_+`-={}|[]\\;':\",./<>?"]]
          [[:COND-true] [:TRIG-modify-color :bg "rgb" [:completed-lifetime 1]]]
        ]
      })
      :lifetime 0
      :spawn-count (Emitter :SCNT-dist-to-target-360)
      :get-spawn-params (SPAR-circle :inverse true :radius 2)
      :birth-delay 45
    })
  ]
  "pulse-twice-explosion" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch ":" :fg 0x888888 :bg 0x44443f :bg-mix 0.9 })
        :speed 0    :lifetime 45   :territorial true
        :triggers @[
          [[:COND-true]
            [:TRIG-modify-color :bg "a" [:custom :origtile
              (fn [self &] (max 0.15 (- 1 (/ (:distance-euc (((self :parent) :particle) :coord) (self :coord))
                                             (:distance-euc (((self :parent) :particle) :coord) (self :target))))))]]]
          [[:COND-true] [:TRIG-lerp-color :bg 0xffffff "rgb" [:sine-custom (fn [self ticks &] (* 8.1 ticks))]]]
        ]
      })
      :lifetime 0
      :spawn-count (Emitter :SCNT-dist-to-target-360)
      :get-spawn-params (SPAR-circle)
    })
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch " " :fg 0 :bg 0x55554f :bg-mix 0.8 })
        :speed 0
        :triggers @[
          # Speed function:
          #
          #  x := completed-journey
          #
          #  sin(-(3x - pi/2)) + 1
          #  --------------------- + 0.15
          #           2
          #
          [[:COND-true] [:TRIG-set-speed (fn [self &] (+ 0.15 (/ (+ (math/sin (- (- (* 3 (:completed-journey self)) (/ math/pi 2)))) 1) 2)))]]
          [[:COND-true] [:TRIG-scramble-glyph "::;.,;::"]]
          [[:COND-true] [:TRIG-lerp-color :bg 0xffffff "rgb" [:completed-journey]]]
        ]
      })
      :lifetime 2
      :spawn-count (fn [&] 360)
      :get-spawn-tile (fn [self ticks ctx tile]
                        (new-tile @{ :ch (tile :ch) :fg (tile :fg) :bg (tile :bg) :bg-mix (math/random) }))
      :get-spawn-params (fn [self ticks ctx coord target]
                          (let [angle (- (:angle target coord)    (* 0.20 (random-choose [-1 0 1])))
                                dist  (- (:distance coord target) (* (math/random) 1.5))
                                ntarg (:move-angle coord dist angle)]
                            [coord ntarg]))
      :get-spawn-speed (Emitter :SSPD-min-sin-ticks)
    })
  ]
 "zap-air-messy" @[
   (new-emitter @{
     :particle (new-particle @{
       :tile (new-tile @{ :ch " " :fg 0 :bg 0xffffff :bg-mix 0 })
       :speed 2
       :triggers @[ [[:COND-parent-dead? 1] [:TRIG-die]] ]
     })
     :lifetime (fn [self &] (+ 8 (:distance ((self :particle) :coord) ((self :particle) :target))))
     :spawn-count 5
     :get-spawn-tile (fn [self ticks ctx tile]
                       (new-tile @{ :ch (tile :ch) :fg (tile :fg) :bg (tile :bg) :bg-mix (math/random) }))
     :get-spawn-params (fn [self ticks ctx coord target]
                         (let [angle (- (:angle target coord)    (* 0.20 (random-choose [-1 0 1])))
                               dist  (- (:distance coord target) (* (math/random) 1.5))
                               ntarg (:move-angle coord dist angle)]
                           [coord ntarg]))
     :get-spawn-speed (Emitter :SSPD-min-sin-ticks)
    })
  ]
  "chargeover-electric"     @[ (template-chargeover SYMB1_CHARS ELEC_BLUE1 0x453555 :direction :in  :speed 0.5 :lifetime 12) ]
  "chargeover-orange-red"   @[ (template-chargeover SYMB1_CHARS   0xff4500 0x440000 :direction :in  :speed 0.5 :lifetime 7 :style :nobg) ]
  "chargeover-white-pink"   @[ (template-chargeover SYMB1_CHARS   0xffffff 0x440000 :direction :in  :speed 0.5 :lifetime 12) ]
  "chargeover-blue-pink"    @[ (template-chargeover SYMB1_CHARS   0x4488aa 0x440000 :direction :in  :speed 0.5 :lifetime 12) ]
  "chargeover-purple-green" @[ (template-chargeover SYMB1_CHARS   0x995599 0x33ff33 :direction :in  :speed 0.5 :lifetime 12) ]
  "chargeover-lines"        @[ (template-chargeover   "|_-=\\/"   0xcacbca 0xffffff                 :speed 0.3             ) ]
  "chargeover-blue-out"     @[ (template-chargeover SYMB1_CHARS   0x11ddff 0x001e85 :direction :out :speed 0.5 :lifetime 12) ]
  "chargeover-noise"        @[ (template-chargeover ["♫" "♩"]     0x00d610 0x00d610 :direction :out :speed 0.5 :lifetime  4 :style :nobg :maxdist 2) ]
  "chargeover-walls"        @[ (template-chargeover "#.,"         CONCRETE VDARK_GREEN :direction :out :speed 0.5 :lifetime 5) ]
  "chargeover-doublegold-candles" @[
    (template-chargeover SYMB1_CHARS 0x3333ff GOLD :direction :out :speed 0.3 :lifetime 7)
    (template-chargeover SYMB1_CHARS LIGHT_GOLD GOLD :direction :in :speed 0.6 :lifetime 10 :which :origin)
  ]
  "beams-ring-amnesia" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "?" :fg 0xd7ff00 :bg 0x5f6600 :bg-mix 0.55 })
        :speed 1.1 :require-los 1
        :triggers @[ [[:COND-true] [:TRIG-scramble-glyph "?!."]] ]
      })
      :lifetime 0
      :spawn-count (fn [self ticks ctx &] ((ctx :bounds) :width))
      :get-spawn-params ((Emitter :SPAR-sweeping-beams))
     })
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "·" :fg 0x777777 :bg 0x999999 :bg-mix 0.1 })
        :speed 1.1 :require-los -1
        :filter (fn [self _t ctx &] (> (:distance-euc (self :coord) (:center (ctx :bounds))) PLAYER_LOS_R))
      })
      :lifetime 0
      :spawn-count (fn [self ticks ctx &] ((ctx :bounds) :width))
      :get-spawn-params ((Emitter :SPAR-sweeping-beams))
     })
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "·" :fg 0x555555 :bg BG :bg-mix 1 })
        :territorial true :speed 0 :require-los 0
        :lifetime (+ (* 2 PLAYER_LOS_R) 5)
        :triggers @[ [[:COND-true] [:TRIG-lerp-color :bg 0x222222 "rgb" [:sine-custom (fn [self ticks &] (* ticks 10))]]] ]
      })
      :lifetime 0
      :spawn-count (fn [self ticks ctx &] 360)
      :get-spawn-params (fn [self ticks ctx coord target]
                          [(:move-angle coord PLAYER_LOS_R (rad (self :total-spawned))) target])
     })
  ]
  "glow-white-gray" @[ (template-lerp-single 0xffffff 0x111111) ]
  "glow-cream"      @[ (template-lerp-single 0xffe377 0x332300) ]
  "glow-purple"     @[ (template-lerp-single 0x995599 0x662266) ]
  "glow-orange-red" @[ (template-lerp-single 0xffdd11 0x851e00) ]
  "glow-blue-dblue" @[ (template-lerp-single 0x11ddff 0x001e85) ]
  "glow-pink"       @[ (template-lerp-single 0xff9999 0x333333) ]

  "zap-awaken-stone" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch "Z" :fg GREEN :bg LIGHT_GREEN :bg-mix 0.7 })
        :speed 1
        :triggers @[
          [[:COND-true] [:TRIG-lerp-color :bg CONCRETE "rgb" [:completed-journey]]]
          [[:COND-percent? 60] [:TRIG-scramble-glyph ".#"]]
          [[:COND-reached-target? true]
           [:TRIG-create-emitter
            (template-chargeover "#.," CONCRETE VDARK_GREEN :direction :out :speed 0.5 :lifetime 12)
          ]]
        ]
      })
      :lifetime 2
    })
  ]
  "zap-torment" @[
    (template-chargeover ASCII_CHARS 0xffd700 0x000066 :direction :in :which :origin :speed 0.5 :lifetime 2 :maxdist 4 :mindist 3)
    (new-emitter-from @{ :birth-delay 2 } (template-lerp-single 0x000066 0xffd700 :lifetime 8 :which :origin))
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch " " :bg 0xffd700 :bg-mix 0.7 })
        :speed 1
        :triggers @[ [[:COND-true] [:TRIG-lerp-color :bg 0x0000ff "rgb" [:completed-journey]]] ]
      })
      :birth-delay 10
      :lifetime 3
     })
  ]
  "explosion-torment" @[
    (new-emitter @{
      :particle (new-particle @{
        :tile (new-tile @{ :ch " " :fg 0 :bg 0x0a0a90 :bg-mix 0.8 })
        :speed 0 :require-los 0
        :triggers @[
          [[:COND-true] [:TRIG-reset-lifetime-once (fn [&] (random-choose [18 19 21 22])) 0]]
          [[:COND-true]
           [:TRIG-lerp-color :bg 0xaa8700 "rgb"
            [:custom (fn [self ticks ctx]
                       (def dist (:distance (self :coord) (ctx :initial)))
                       (min 1 (/ (* dist ticks) 150)))
             :inverse]]]
        ]
      })
      :lifetime 5
      :spawn-count (fn [self ticks ctx &] (/ (length (ctx :target)) 5))
      :get-spawn-params (fn [self ticks ctx coord target]
                          (if (>= (self :total-spawned) (length target))
                            (break [nil nil]))
                          [(target (self :total-spawned)) coord])
      })
  ]
})

(defn animation-init [initial target boundsx boundsy bounds-width bounds-height emitters-set]
  (def area-size (new-rect (new-coord boundsx boundsy) bounds-width bounds-height))
  (def emitters (deepclone (emitters-table emitters-set)))

  (if (not emitters)
    (panic "Animation %s doesn't exist." emitters-set))

  (each emitter emitters
    (put emitter :initial initial)
    (put emitter :target target)
    (if (and (initial :x) (initial :y))
      (put (emitter :particle) :coord initial))
    (if (and (= (type target) :table) (target :x) (target :y))
      (put (emitter :particle) :target target)))

  (new-context initial target area-size emitters))

(defn animation-tick [ctx ticks]

  (var live-emitters 0)
  (loop [i :range [0 (length (ctx :emitters))]]
    (def emitter ((ctx :emitters) i))
    (if (not (emitter :dead))
      (if (:tick emitter ticks ctx)
        (put emitter :dead true)
        (++ live-emitters))))

  # Make a note of each territorial particle for later
  (var particle-map @{})
  (each particle (ctx :particles)
    (if (and (not (particle :dead))
             (particle :territorial))
      (let [particle-coord [(math/round ((particle :coord) :y))
                            (math/round ((particle :coord) :x))]]
        (put particle-map particle-coord (particle :id)))))

  (var particles @[])
  (loop [i :range [0 (length (ctx :particles))]]
    (def particle ((ctx :particles) i))
    (if (not (particle :dead))
      (do
        (var trespassing false)
        (if (:tick particle ticks ctx)
          (put particle :dead true))

        # Filter out trespassers
        (if (not (particle :dead))
          (let [particle-coord [(math/round ((particle :coord) :y))
                                (math/round ((particle :coord) :x))]]
            (if (and (particle-map particle-coord)
                     (not (= (particle-map particle-coord) (particle :id))))
              (do (put particle :dead true)
                  (set trespassing true)))))

        (if (and (:contains? (ctx :bounds) (particle :coord))
                 (not (:filter particle ticks ctx))
                 (not trespassing))
          (array/push particles @[((particle :tile) :ch)
                                  ((particle :tile) :fg)
                                  ((particle :tile) :bg)
                                  ((particle :tile) :bg-mix)
                                  (math/round ((particle :coord) :x))
                                  (math/round ((particle :coord) :y))
                                  (particle :require-los)
                                  (particle :require-nonwall)])))))
  (shuffle-in-place particles)

  # Insert filler particle if no live particles (but there are still live emitters)
  # to prevent effect from ending too soon
  (if (and (= (length particles) 0)
           (> live-emitters 0))
    (array/push particles @[" " 0 0 0 99999 99999 0]))

  particles)
