## The TEXTS of the weather sample, in the languages it speaks: French (the default) and English. The French strings are
## the translation the app asks for, not a slip in the language of the repository; a language is one more table below, and
## nothing in the code that reads them changes — except that the names of the days come from date.weekdayName, which
## knows "en" and "fr" only, so a language of this list that it does not know must have its own table of them.
##
## Every language has the same keys, which weather_test.ol checks. A text is a string, except the ones that take a figure
## or a name, which are functions of it. The reasons an answer cannot be read (forecast.ol) and the kinds of sky are
## named by a key, and said here.

import "../lib/i18n.ol"

const LANGUAGES = ["fr", "en"]      ## the order of the language list; the first one is the default

const TEXTS = {
    fr: {
        name: "Français",
        windowTitle: "Météo",
        today: "Auj.",
        conditions: "Conditions",
        feelsLike: "Ressenti",
        wind: "Vent",
        forecastTitle: func(n)
            return "Prévisions sur {n} jours"
        end,
        highLow: func(high, low)
            return "Max. {high}°   Min. {low}°"
        end,
        loading: "Chargement…",
        lookingFor: func(name)
            return "Recherche de {name}…"
        end,
        noPlace: func(name)
            return "Aucun lieu ne s'appelle {name}."
        end,
        noNetwork: "Cette version n'a pas de réseau : la météo est demandée depuis le navigateur.",
        timeout: "Le service n'a pas répondu à temps.",
        noAnswer: "Pas de réponse : le réseau est coupé, ou le service n'autorise pas cette page à le consulter.",
        answered: func(status)
            return "Le service a répondu {status}."
        end,
        cannotRead: func(why)
            return "Réponse illisible : {why}."
        end,
        hint: "< >  ou glisser pour changer de ville      saisir un nom, ou toucher la loupe",
        cityLabel: "Ville",
        cityPlaceholder: "Nom de la ville",
        languageLabel: "Langue",
        reasons: {
            notJson: "la réponse n'est pas du JSON",
            noWeather: "la réponse ne contient pas de météo",
            nowMissing: "la météo actuelle est absente",
            daysMissing: "les prévisions des jours sont absentes",
            badDate: "une date des prévisions n'est pas une date",
            noPlace: "aucun lieu de ce nom",
            noPosition: "le lieu n'a pas de position"
        },
        skyUnknown: func(code)
            return "Code météo {code}"
        end,
        sky: {
            clear: "Ciel dégagé",
            mainlyClear: "Plutôt dégagé",
            partlyCloudy: "Partiellement nuageux",
            overcast: "Couvert",
            fog: "Brouillard",
            freezingFog: "Brouillard givrant",
            lightDrizzle: "Bruine légère",
            drizzle: "Bruine",
            heavyDrizzle: "Forte bruine",
            freezingDrizzle: "Bruine verglaçante",
            lightRain: "Pluie légère",
            rain: "Pluie",
            heavyRain: "Forte pluie",
            freezingRain: "Pluie verglaçante",
            lightSnow: "Faible neige",
            snow: "Neige",
            heavySnow: "Forte neige",
            snowGrains: "Grains de neige",
            rainShowers: "Averses",
            violentShowers: "Fortes averses",
            snowShowers: "Averses de neige",
            thunderstorm: "Orage",
            thunderstormHail: "Orage et grêle"
        },
        cities: {
            paris: ["Paris", "France"],
            london: ["Londres", "Royaume-Uni"],
            newYork: ["New York", "États-Unis"],
            tokyo: ["Tokyo", "Japon"],
            sydney: ["Sydney", "Australie"],
            reykjavik: ["Reykjavik", "Islande"],
            cairo: ["Le Caire", "Égypte"],
            rio: ["Rio de Janeiro", "Brésil"]
        }
    },
    en: {
        name: "English",
        windowTitle: "Weather",
        today: "Today",
        conditions: "Conditions",
        feelsLike: "Feels like",
        wind: "Wind",
        forecastTitle: func(n)
            return "{n}-day forecast"
        end,
        highLow: func(high, low)
            return "High {high}°   Low {low}°"
        end,
        loading: "Loading…",
        lookingFor: func(name)
            return "Looking for {name}…"
        end,
        noPlace: func(name)
            return "No place is called {name}."
        end,
        noNetwork: "This build has no network: the weather is asked from the browser.",
        timeout: "The service did not answer in time.",
        noAnswer: "No answer: the network is down, or the service does not allow this page to ask.",
        answered: func(status)
            return "The service answered {status}."
        end,
        cannotRead: func(why)
            return "Cannot read the answer: {why}."
        end,
        hint: "< >  or drag for another city      type a name, or touch the magnifier",
        cityLabel: "City",
        cityPlaceholder: "City name",
        languageLabel: "Language",
        reasons: {
            notJson: "the answer is not JSON",
            noWeather: "the answer holds no weather",
            nowMissing: "the weather of now is missing",
            daysMissing: "the forecast of the days is missing",
            badDate: "a date of the forecast is not a date",
            noPlace: "no such place",
            noPosition: "the place has no position"
        },
        skyUnknown: func(code)
            return "Weather code {code}"
        end,
        sky: {
            clear: "Clear sky",
            mainlyClear: "Mainly clear",
            partlyCloudy: "Partly cloudy",
            overcast: "Overcast",
            fog: "Fog",
            freezingFog: "Freezing fog",
            lightDrizzle: "Light drizzle",
            drizzle: "Drizzle",
            heavyDrizzle: "Heavy drizzle",
            freezingDrizzle: "Freezing drizzle",
            lightRain: "Light rain",
            rain: "Rain",
            heavyRain: "Heavy rain",
            freezingRain: "Freezing rain",
            lightSnow: "Light snow",
            snow: "Snow",
            heavySnow: "Heavy snow",
            snowGrains: "Snow grains",
            rainShowers: "Rain showers",
            violentShowers: "Violent showers",
            snowShowers: "Snow showers",
            thunderstorm: "Thunderstorm",
            thunderstormHail: "Thunderstorm, hail"
        },
        cities: {
            paris: ["Paris", "France"],
            london: ["London", "United Kingdom"],
            newYork: ["New York", "United States"],
            tokyo: ["Tokyo", "Japan"],
            sydney: ["Sydney", "Australia"],
            reykjavik: ["Reykjavik", "Iceland"],
            cairo: ["Cairo", "Egypt"],
            rio: ["Rio de Janeiro", "Brazil"]
        }
    }
}

useLanguages(LANGUAGES, TEXTS, "lang")

## The words of a kind of sky of forecast.ol: its table entry, or the code alone when the table does not know it.
func skyText(sky)
    if sky.key == nil then
        return tr("skyUnknown")(sky.code)
    end
    return tr("sky")[sky.key]
end

## The words of a reason an answer cannot be read (a key of forecast.ol).
func reasonText(key)
    return tr("reasons")[key] or key
end
