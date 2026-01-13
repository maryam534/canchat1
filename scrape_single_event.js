const path = require('path')
const fs = require('fs')
const puppeteer = require('puppeteer')

const profileDir = path.join(__dirname, 'pp-profile')
fs.mkdirSync(profileDir, { recursive: true })

function log(msg) { console.log(`[${new Date().toISOString()}] ${msg}`) }

// args: --event-id <id> --output-file <name>
const args = process.argv.slice(2)
let eventId = null
let outputFile = null
for (let i = 0; i < args.length; i++) {
  const a = args[i]
  if (a === '--event-id' && i + 1 < args.length) eventId = args[++i]
  else if (a.startsWith('--event-id=')) eventId = a.split('=')[1]
  else if (a === '--output-file' && i + 1 < args.length) outputFile = args[++i]
  else if (a.startsWith('--output-file=')) outputFile = a.split('=')[1]
}

if (!eventId) { console.error('Missing --event-id'); process.exit(1) }
if (!outputFile) outputFile = `auction_${eventId}_lots.jsonl`

const inProgressDir = path.join(__dirname, 'allAuctionLotsData_inprogress')
const finalDir = path.join(__dirname, 'allAuctionLotsData_final')
fs.mkdirSync(inProgressDir, { recursive: true })
fs.mkdirSync(finalDir, { recursive: true })

const resolvedOutput = path.isAbsolute(outputFile)
  ? outputFile
  : path.resolve(__dirname, outputFile)

// Avoid double-prefixing if caller already points inside inProgressDir
const inProgressFile = resolvedOutput.startsWith(inProgressDir + path.sep)
  ? resolvedOutput
  : path.join(inProgressDir, path.basename(resolvedOutput))
fs.mkdirSync(path.dirname(inProgressFile), { recursive: true })
const finalFile = path.join(finalDir, `auction_${eventId}_lots.json`)

;(async () => {
  // const browser = await puppeteer.launch({
  //   headless: 'new',
  //   args: [
  //     '--no-sandbox',
  //     '--disable-dev-shm-usage',
  //     `--user-data-dir=${profileDir}`
  //   ],
  //   defaultViewport: { width: 1280, height: 800 }
  // })

  const browser = await puppeteer.launch({
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    headless: 'new',
    args: ['--no-sandbox']
    });

  const page = await browser.newPage()
  page.setDefaultTimeout(45000)
  page.setDefaultNavigationTimeout(60000)

  try {
    const baseUrl = `https://www.numisbids.com/sale/${eventId}`
    log(`Navigating: ${baseUrl}`)
    await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })

    // View all lots if present
    try {
      const viewAllHref = await page.evaluate(() => {
        const links = Array.from(document.querySelectorAll('a'))
        const m = links.find(a => /view\s*all\s*lots/i.test(a.textContent || ''))
        return m ? m.getAttribute('href') : null
      })
      if (viewAllHref) {
        const fullUrl = new URL(viewAllHref, window.location.href).href
        log(`Following View all lots -> ${fullUrl}`)
        await page.goto(fullUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })
      }
    } catch {}

    // Auction metadata and total pages
    let auctionName = ''
    let auctionTitle = ''
    let eventDate = ''
    let totalPages = 1

    try {
      const meta = await page.evaluate(() => {
        const textDiv = document.querySelector('.text')
        const auctionName = textDiv?.querySelector('.name')?.textContent?.trim() || ''
        const bTags = textDiv ? Array.from(textDiv.querySelectorAll('b')) : []
        const titlePart = bTags[0]?.textContent?.trim() || ''
        const fullHtml = textDiv?.innerHTML || ''
        const match = fullHtml.match(/<b>.*?<\/b>&nbsp;&nbsp;([^<]+)/)
        const eventDate = match ? match[1].trim() : ''

        const pageInfo = document.querySelector('.salenav-top .small')?.textContent || ''
        const pagesMatch = pageInfo.match(/Page\s+\d+\s+of\s+(\d+)/i)
        const totalPages = pagesMatch ? parseInt(pagesMatch[1], 10) : 1

        return { auctionName, auctionTitle: `${auctionName}, ${titlePart}`.trim(), eventDate, totalPages }
      })
      auctionName = meta.auctionName
      auctionTitle = meta.auctionTitle
      eventDate = meta.eventDate
      totalPages = meta.totalPages
    } catch {}

    fs.writeFileSync(inProgressFile, '')
    const seenLots = new Set()

    for (let currentPage = 1; currentPage <= totalPages; currentPage++) {
      const pageUrlBase = await page.evaluate(() => window.location.href.split('?')[0])
      const pageUrl = `${pageUrlBase}?pg=${currentPage}`
      log(`Auction ${eventId} — Page ${currentPage}`)
      await page.goto(pageUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })

      const lotHandles = await page.$$('.browse')
      for (const lot of lotHandles) {
        try {
          const lotNumber = await lot.$eval('.lot a', el => el.textContent.trim().replace(/^Lot\s+/i, ''))
          if (seenLots.has(lotNumber)) continue

          const relLotUrl = await lot.$eval('a[href*="/lot/"]', el => el.getAttribute('href'))
          const lotUrl = new URL(relLotUrl, 'https://www.numisbids.com').href
          const lotName = await lot.$eval('.summary a', el => el.textContent.trim())
          const description = lotName.split('.')[0]
          const thumbImage = await lot.$eval('img', el => {
            const src = el.getAttribute('src') || ''
            return src.startsWith('http') ? src : 'https:' + src
          })
          const startingPrice = await lot.$eval('.estimate span', el => el.textContent.trim()).catch(() => '')
          const realizedPrice = await lot.$eval('.realized span', el => el.textContent.trim()).catch(() => '')

          const dpage = await browser.newPage()
          dpage.setDefaultTimeout(30000)
          await dpage.goto(lotUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })
          await dpage.waitForSelector('.viewlottext', { timeout: 10000 }).catch(() => {})

          const details = await dpage.evaluate(() => {
            const activeCat = document.querySelector('#activecat span a:last-of-type')
            const rawCategory = activeCat ? activeCat.textContent.trim() : ''
            const category = rawCategory.replace(/^[A-Z]\.[\s\u00A0]*/, '').replace(/\s*\(\d+\)\s*$/, '').trim()

            const descEl = document.querySelector('.viewlottext > .description:last-of-type')
            let fullDesc = ''
            if (descEl) {
              fullDesc = descEl.innerHTML
                .replace(/<br\s*\/?>(\s*)/gi, '\n')
                .replace(/<[^>]+>/g, '')
                .trim()
            }

            const img = document.querySelector('.viewlotimg img')?.getAttribute('src') || ''
            const fullImage = img ? (img.startsWith('http') ? img : 'https:' + img) : ''

            return { category, fullDescription: fullDesc, fullImage }
          })

          await dpage.close()

          const lotData = {
            auctionid: String(eventId),
            loturl: lotUrl,
            auctionname: auctionName,
            auctiontitle: auctionTitle,
            eventdate: eventDate,
            category: details.category,
            startingprice: startingPrice,
            realizedprice: realizedPrice,
            imagepath: details.fullImage || thumbImage,
            fulldescription: details.fullDescription,
            lotnumber: lotNumber,
            shortdescription: lotName,
            lotname: description
          }

          fs.appendFileSync(inProgressFile, JSON.stringify(lotData) + '\n')
          seenLots.add(lotNumber)
          log(`Scraped lot ${lotNumber}`)
        } catch (err) {
          console.warn(`Lot error: ${err.message}`)
        }
      }
    }

    const lines = fs.readFileSync(inProgressFile, 'utf-8')
      .split('\n').filter(Boolean).map(l => JSON.parse(l))
    fs.writeFileSync(finalFile, JSON.stringify(lines, null, 2))
    log(`Saved final JSON: ${finalFile}`)
  } catch (e) {
    console.error(e)
    process.exitCode = 1
  } finally {
    await browser.close()
  }
})()
