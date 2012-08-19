
class LaserTail

    constructor: (@container) ->
        # Create a Raphael canvas
        @paper = Raphael(@container, 320, 200)
        # Set up resizing
        @resizeRenderer()
        window.addEventListener('resize', (=> @resizeRenderer()), false)
        # Create some data containers
        @hosts = []
        @urls = []
        @hits = []
        @hostHeight = 20
        @urlHeight = 20
        @leftWidth = 210
        @rightWidth = 210
        @laserDecay = 5

    # Resizes the main viewport to match the current window
    resizeRenderer: ->
        @width = $(@container).width()
        @height = $(@container).height()
        @paper.setSize(@width, @height, false)

    # Redraws the page
    redraw: ->
        # For every host without a div, give it one, and set positions
        index = 0
        for host in @hosts
            # Make a div if needed
            if !host.div
                host.div = $("<div class='host'>" + host.name + "</div>")
                $(@container).append(host.div)
            # Set position
            sectionHeight = @height / @hosts.length
            middle = (sectionHeight * index) + (sectionHeight / 2)
            $(host.div).css({left: 0, top: middle - (@hostHeight / 2)})
            host.point = [@leftWidth, middle]
            # Update index
            index += 1
        # Same for URLs
        index = 0
        for url in @urls
            # Make a div if needed
            if !url.div
                url.div = $("<div class='url'>" + url.path + "</div>")
                $(@container).append(url.div)
            # Set position
            sectionHeight = @height / @urls.length
            middle = (sectionHeight * index) + (sectionHeight / 2)
            $(url.div).css({right: 0, top: middle - (@urlHeight / 2)})
            url.point = [@width - @rightWidth, middle]
            # Update index
            index += 1
        # Draw any hits in the queue
        for hit in @hits
            host = @getHost(hit.hostName)
            url = @getUrl(hit.urlPath)
            path = @paper.path("M" + host.point[0] + "," + host.point[1] + "L" + url.point[0] + "," + url.point[1])
            path.attr("stroke", "#aad")
            path.attr("stroke-width", "3")
            ((path, delay) => 
                path.animate({opacity: 0}, delay, "linear", ->
                    path.remove();
                )
            )(path, @laserDecay * 1000)
        @hits = []

    # Gets a host by name
    getHost: (hostName) ->
        for host in @hosts
            if host.name == hostName
                return host
        return undefined

    # Gets a url by path
    getUrl: (urlPath) ->
        for url in @urls
            if url.path == urlPath
                return url
        return undefined

    # Adds a hit to the page
    addHit: (hostName, urlPath, noRedraw) ->
        time = (new Date()).getTime()
        # Add a host record if there isn't one
        host = @getHost(hostName)
        if host?
            host.lastSeen = time
        else
            @hosts.push({name: hostName, lastSeen: time})
        # Same with urls
        url = @getUrl(urlPath)
        if url?
            url.lastSeen = time
        else
            @urls.push({path: urlPath, lastSeen: time})
        # Queue up a laser line draw
        @hits.push({hostName: hostName, urlPath: urlPath})
        # Refresh the view if needed
        if !noRedraw
            @redraw()

    # Adds many hits to the page at once
    addHits: (hits) ->
        for hit in hits
            @addHit(hit.host, hit.url, true)
        @redraw()

    fetchHits: (url) ->
        $.getJSON(url, (data) ->
            addHits(data)
            setTimeout(fetchHits(url), 300)
        )

window.LaserTail = LaserTail
