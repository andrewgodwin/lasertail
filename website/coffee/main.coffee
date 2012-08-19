
class LaserTail

    constructor: (@container) ->
        # Create a Raphael canvas
        @paper = Raphael(@container, 320, 200)
        # Create some data containers
        @hits = []
        @hostHeight = 14
        @urlHeight = 14
        @leftWidth = 210
        @rightWidth = 210
        @laserDecay = 10
        @laserWidth = 2
        @hostExpiry = 30
        @urlExpiry = 60
        @refreshInterval = 0.3
        # Set up resizing and expiry
        @resizeRenderer()
        window.addEventListener('resize', (=> @resizeRenderer()), false)
        @expireOld()

    # Resizes the main viewport to match the current window
    resizeRenderer: ->
        @width = $(@container).width()
        @height = $(@container).height()
        @paper.setSize(@width, @height, false)
        # Reset the hosts and urls to empty lists of the right length
        @hosts = (null for i in [0..Math.floor(@height/@hostHeight)])
        @urls = (null for i in [0..Math.floor(@height/@urlHeight)])
        $(".host").remove()
        $(".url").remove()


    # Redraws the page
    redraw: ->
        # For every host without a div, give it one, and set positions
        for host, index in @hosts
            if host?
                # Make a div if needed
                if !host.div
                    host.div = $("<div class='host'>" + host.name + "</div>")
                    $(@container).append(host.div)
                    # Set position
                    middle = (@hostHeight * index) + (@hostHeight / 2)
                    $(host.div).css({left: -@leftWidth, top: middle - (@hostHeight / 2)}).animate({left: 0})
                    host.point = [@leftWidth, middle]
        # Same for URLs
        for url, index in @urls
            if url?
                # Make a div if needed
                if !url.div
                    url.div = $("<div class='url'>" + url.path + "</div>")
                    $(@container).append(url.div)
                    # Set position
                    middle = (@urlHeight * index) + (@urlHeight / 2)
                    $(url.div).css({right: -@rightWidth, top: middle - (@urlHeight / 2)}).animate({right: 0})
                    url.point = [@width - @rightWidth, middle]
        # Draw any hits in the queue
        for hit in @hits
            host = @getHost(hit.host)
            url = @getUrl(hit.url)
            if host? and url?
                path = @paper.path("M" + host.point[0] + "," + host.point[1] + "L" + url.point[0] + "," + url.point[1])
                color = "#aad"
                if hit.status == 200
                    color = "#ada"
                else if hit.status == 301 or hit.status == 302
                    color = "#dda"
                else if hit.status == 404
                    color = "#daa"
                else if hit.status == 500
                    color = "#b66"
                path.attr("stroke", color)
                path.attr("stroke-width", @laserWidth)
                ((path, delay) => 
                    path.animate({opacity: 0}, delay, "linear", ->
                        path.remove();
                    )
                )(path, @laserDecay * 1000)
        @hits = []

    # Gets a host by name
    getHost: (hostName) ->
        for host in @hosts
            if host? and host.name == hostName
                return host
        return undefined

    # Gets a url by path
    getUrl: (urlPath) ->
        for url in @urls
            if url? and url.path == urlPath
                return url
        return undefined

    # Places an object into an array in the place with the biggest gap
    placeArray: (array, thing) ->
        # Step one - try to find a gap while remembering the oldest member.
        # If there are gaps we'll use a random one
        oldest = undefined
        oldest_index = undefined
        gaps = []
        for member, index in array
            if not member?
                gaps.push(index)
            if member? and (not oldest? or member.lastSeen < oldest.lastSeen)
                oldest_index = index
                oldest = member
        if gaps
            rand = Math.random()
            rand *= gaps.length
            rand = Math.floor(rand)
            array[gaps[rand]] = thing
            return
        # Step two - remove the oldest one and put it there
        array[oldest_index] = thing
        if oldest.path?
            @removeUrl(oldest)
        else
            @removeHost(oldest)

    # Adds a hit to the page
    addHit: (hit, noRedraw) ->
        time = (new Date()).getTime() / 1000
        # Add a host record if there isn't one
        host = @getHost(hit.host)
        if host?
            host.lastSeen = time
        else
            @placeArray(@hosts, {name: hit.host, lastSeen: time})
        # Same with urls
        url = @getUrl(hit.url)
        if url?
            url.lastSeen = time
        else
            @placeArray(@urls, {path: hit.url, lastSeen: time})
        # Queue up a laser line draw
        @hits.push(hit)
        # Refresh the view if needed
        if !noRedraw
            @redraw()

    # Adds many hits to the page at once
    addHits: (hits) ->
        for hit in hits
            @addHit(hit, true)
        @redraw()

    # Runs a task to fetch hits from a polling server
    fetchHits: (url) ->
        # Create a watchdog in case the connection drops
        ((oldSince) => setTimeout((=>
            if oldSince == @since
                @fetchHits(url)
        ), @refreshInterval * 5000))(@since)
        # Get the JSON
        $.getJSON(url + "?since=" + @since, (data) =>
            @addHits(data.hits)
            @since = data.since
            setTimeout((=> @fetchHits(url)), @refreshInterval * 1000)
        )

    # Removes a host (doesn't touch @hosts, do that first)
    removeHost: (host) ->
        $(host.div).animate({left: -@leftWidth}, -> $(this).remove())

    # Removes a url (doesn't touch @urls, do that first)
    removeUrl: (url) ->
        $(url.div).animate({right: -@rightWidth}, -> $(this).remove())

    # A task to expire old URLs/hosts
    expireOld: ->
        time = (new Date()).getTime() / 1000
        for host, index in @hosts
            if host?
                percentageExpired = (time - host.lastSeen) / @hostExpiry
                if percentageExpired >= 1
                    @removeHost(host)
                    @hosts[index] = null
                else
                    $(host.div).css({opacity: 1 - 0.8 * Math.min(percentageExpired*2, 1)})
        for url, index in @urls
            if url?
                percentageExpired = (time - url.lastSeen) / @urlExpiry
                if percentageExpired >= 1
                    @removeUrl(url)
                    @urls[index] = null
                else
                    $(url.div).css({opacity: 1 - 0.8 * Math.min(percentageExpired*2, 1)})
        setTimeout((=> @expireOld()), 300)

window.LaserTail = LaserTail
