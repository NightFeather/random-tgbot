require 'sinatra'
require "json"
require 'net/https'
require 'nokogiri'

if File.exists? ".env"
  File.open(".env", mode: "rb") do |f|
    f.each do |l|
      key, value = l.strip!.split("=",2)
      ENV[key] = value
    end
  end
end

FEATURE_MAP = {
  "telegram" => (ENV.key?("TELEGRAM_TOKEN") and ENV.key?("TELEGRAM_CHATID"))
}

if not FEATURE_MAP["telegram"]
  puts "missing required enviroment variable, disabling telegram features."
end

def subproc_call(*cmd)
  sr,sw = IO.pipe
  er,ew = IO.pipe
  fork do
    sr.close
    er.close
    STDOUT.reopen(sw)
    STDERR.reopen(ew)
    exec(*cmd)
  end
  Process.wait
  sw.close
  ew.close
  sout = sr.read
  sr.close
  eout = er.read
  er.close
  return [$?.exitstatus, sout, eout]
end

get "/" do
  %{
  <!DOCTYPE html>
  <html>
  <head>
  <style rel="stylesheet" type="text/css">
    textarea {
      width: 80em;
      height: 60em;
    }
  </style>
  </head>
  <body>
  <div>
  <input name="data">
  #{FEATURE_MAP["telegram"] ? '<button data-target="/bot">Send to bot</button>' : ""}
  <button data-target="/ytsum">YouTube Summary</button>
  <button data-target="/resolv">Solve Redirection</button>
  </div>
  <textarea spellcheck="false"></textarea>
  <script>
    document.querySelectorAll("button")
      .forEach(el => el.addEventListener("click", ev => {
        let data = new FormData()
        data.append('data', document.querySelector("input").value)
        document.querySelector("textarea").value = "Loading..."
        fetch(ev.target.dataset.target,
          {
            method: "POST",
            body: data
          }
        )
        .then(resp => resp.text())
        .then(result => { document.querySelector("textarea").value = result })
      }))
  </script>
  </body>
  </html>
  }
end

if FEATURE_MAP["telegram"] 
  post "/bot" do
    data = params['data']
    resp = Net::HTTP.post_form(
      URI("https://api.telegram.org/bot#{ENV["TELEGRAM_TOKEN"]}/sendMessage"),
      {
        chat_id: ENV["TELEGRAM_CHATID"],
        text: data,
        disable_web_page_preview: false,
      }
    )
    status resp.code
    return JSON.pretty_generate JSON.parse(resp.body)
  end
end

post "/ytsum" do
  r,s,e = subproc_call "sh", "-c",
    "/usr/bin/youtube-dl" + " -j" +
    " --socket-timeout 1" +
    " '#{params['data'].strip}'" +
    " | jq -r '.title, (.uploader+\" (\"+.uploader_url+\")\"), \"\", .description, \"\", (.tags|join(\",\"))'"
  return [
    r > 0 ? 400 : 200,
    [
      "#{r}\n",
      "-"*20+"\n",
      s,
      "-"*20+"\n",
      e
    ]
  ]
end

post "/resolv" do
  jumps = [params["data"].strip]
  resp = nil
  loop do
    uri = URI(jumps.last)
    resp = Net::HTTP.get_response(uri, {
      'User-Agent': "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.93 Safari/537.36"
    })
    if resp.is_a? Net::HTTPRedirection
      jumps << resp['Location']
    else
      dom = Nokogiri::HTML.parse resp.body
      equiv_refresh = dom.css('meta[http-equiv][content]').select { |node| node['http-equiv'].downcase == 'refresh' }

      if not equiv_refresh.empty?
        target = equiv_refresh[-1]['content'].split(';', 2)[1].strip
        if target =~ /^url=/i
          jumps << target[4..-1]
        elsif target =~ /^\//
          jumps << "#{uri.scheme}://#{uri.host}#{target}"
        else
          jumps << "#{uri.scheme}://#{uri.host}/#{File.dirname(uri.path)}/#{target}"
        end
      elsif uri.host == 'reurl.cc'
        jumps << dom.css('#form input[name="url"]')[0]['value']
      else
        title = dom.css("head > title")[0]
        if title
          jumps << title.text
        else
          jumps << "## no title ##"
        end
        break
      end
    end
  end
  return [
    200,
    jumps.join("\n")
  ]
end
