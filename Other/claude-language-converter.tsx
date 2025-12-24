import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown, ArrowRight, Code, Loader2 } from 'lucide-react';

const TRANSLATIONS = {
  "en-US": {
    "appTitle": "CodeVerter",
    "appSubtitle": "Programming Language Converter",
    "sourceLanguagePlaceholder": "Source Language",
    "targetLanguagePlaceholder": "Target Language",
    "convertButton": "Convert Code",
    "converting": "Converting...",
    "sourceCodeTitle": "Source Code",
    "convertedCodeTitle": "Converted Code",
    "sourceCodePlaceholder": "Enter your source code here...",
    "convertedCodePlaceholder": "Converted code will appear here...",
    "convertingPlaceholder": "Converting...",
    "footerText1": "CodeVerter uses Claude AI to convert code between programming languages.",
    "footerText2": "Results may require manual review and adjustment.",
    "searchLanguagesPlaceholder": "Search languages...",
    "noLanguagesFound": "No languages found",
    "errorEmptyCode": "Please enter some code to convert",
    "errorConversionFailed": "Failed to convert code. Please try again.",
    "exampleComment": "# Example Python code"
  },
  /* LOCALE_PLACEHOLDER_START */
  "es-ES": {
    "appTitle": "CodeVerter",
    "appSubtitle": "Convertidor de Lenguajes de Programación",
    "sourceLanguagePlaceholder": "Lenguaje de Origen",
    "targetLanguagePlaceholder": "Lenguaje de Destino",
    "convertButton": "Convertir Código",
    "converting": "Convirtiendo...",
    "sourceCodeTitle": "Código de Origen",
    "convertedCodeTitle": "Código Convertido",
    "sourceCodePlaceholder": "Ingresa tu código fuente aquí...",
    "convertedCodePlaceholder": "El código convertido aparecerá aquí...",
    "convertingPlaceholder": "Convirtiendo...",
    "footerText1": "CodeVerter utiliza Claude AI para convertir código entre lenguajes de programación.",
    "footerText2": "Los resultados pueden requerir revisión y ajuste manual.",
    "searchLanguagesPlaceholder": "Buscar lenguajes...",
    "noLanguagesFound": "No se encontraron lenguajes",
    "errorEmptyCode": "Por favor ingresa código para convertir",
    "errorConversionFailed": "Error al convertir el código. Por favor intenta de nuevo.",
    "exampleComment": "# Código Python de ejemplo"
  }
  /* LOCALE_PLACEHOLDER_END */
};

const appLocale = '{{APP_LOCALE}}';
const browserLocale = navigator.languages?.[0] || navigator.language || 'en-US';
const findMatchingLocale = (locale) => {
  if (TRANSLATIONS[locale]) return locale;
  const lang = locale.split('-')[0];
  const match = Object.keys(TRANSLATIONS).find(key => key.startsWith(lang + '-'));
  return match || 'en-US';
};
const locale = (appLocale !== '{{APP_LOCALE}}') ? findMatchingLocale(appLocale) : findMatchingLocale(browserLocale);
const t = (key) => TRANSLATIONS[locale]?.[key] || TRANSLATIONS['en-US'][key] || key;

const CodeVerter = () => {
  // Programming languages
  const languages = [
    'Python', 'JavaScript', 'TypeScript', 'Bash', 'PowerShell', 'CMD', 'Fish',
    'Java', 'C++', 'C#', 'C', 'Go', 'Rust', 'Swift', 'Kotlin', 'PHP', 'Ruby', 
    'Scala', 'R', 'MATLAB', 'Perl', 'Haskell', 'Lua', 'Dart', 'Elixir', 'F#', 
    'Clojure', 'AutoHotkey', 'Objective-C', 'Visual Basic'
  ];

  const [sourceCode, setSourceCode] = useState(`${t('exampleComment')}\ndef fibonacci(n):\n    if n <= 1:\n        return n\n    return fibonacci(n-1) + fibonacci(n-2)\n\nprint(fibonacci(10))`);
  const [targetCode, setTargetCode] = useState('');
  const [sourceLanguage, setSourceLanguage] = useState('Python');
  const [targetLanguage, setTargetLanguage] = useState('JavaScript');
  const [isConverting, setIsConverting] = useState(false);
  const [error, setError] = useState('');

  const convertCode = async () => {
    if (!sourceCode.trim()) {
      setError(t('errorEmptyCode'));
      return;
    }

    setIsConverting(true);
    setError('');
    setTargetCode('');

    try {
      const prompt = `Convert the following ${sourceLanguage} code to ${targetLanguage}. Only return the converted code without any explanation or markdown formatting. Please respond in ${locale} language:

${sourceCode}`;

      const response = await window.claude.complete(prompt);
      setTargetCode(response);
    } catch (err) {
      setError(t('errorConversionFailed'));
      console.error('Conversion error:', err);
    } finally {
      setIsConverting(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div className="flex items-center gap-3">
          <Code className="w-8 h-8 text-blue-400" />
          <h1 className="text-2xl font-bold text-white">{t('appTitle')}</h1>
          <span className="text-gray-400 text-sm ml-2">{t('appSubtitle')}</span>
        </div>
      </div>

      {/* Main Content */}
      <div className="p-6">
        <div className="max-w-7xl mx-auto">
          {/* Language Selection */}
          <div className="flex items-center justify-center gap-4 mb-6">
            <LanguageDropdown 
              value={sourceLanguage}
              onChange={setSourceLanguage}
              languages={languages}
              placeholder={t('sourceLanguagePlaceholder')}
            />
            <ArrowRight className="w-6 h-6 text-gray-400" />
            <LanguageDropdown 
              value={targetLanguage}
              onChange={setTargetLanguage}
              languages={languages}
              placeholder={t('targetLanguagePlaceholder')}
            />
          </div>

          {/* Convert Button */}
          <div className="flex justify-center mb-6">
            <button
              onClick={convertCode}
              disabled={isConverting}
              className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-800 disabled:cursor-not-allowed px-6 py-3 rounded-lg font-medium transition-colors"
            >
              {isConverting ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  {t('converting')}
                </>
              ) : (
                <>
                  <Code className="w-5 h-5" />
                  {t('convertButton')}
                </>
              )}
            </button>
          </div>

          {/* Error Message */}
          {error && (
            <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg mb-6 text-center">
              {error}
            </div>
          )}

          {/* Code Panels */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Source Code Panel */}
            <div className="bg-gray-800 rounded-lg overflow-hidden">
              <div className="bg-gray-700 px-4 py-3 border-b border-gray-600">
                <h3 className="font-medium text-gray-200">{t('sourceCodeTitle')} ({sourceLanguage})</h3>
              </div>
              <textarea
                value={sourceCode}
                onChange={(e) => setSourceCode(e.target.value)}
                className="w-full h-96 p-4 bg-gray-800 text-gray-100 font-mono text-sm resize-none border-none outline-none"
                placeholder={t('sourceCodePlaceholder')}
              />
            </div>

            {/* Target Code Panel */}
            <div className="bg-gray-800 rounded-lg overflow-hidden">
              <div className="bg-gray-700 px-4 py-3 border-b border-gray-600">
                <h3 className="font-medium text-gray-200">{t('convertedCodeTitle')} ({targetLanguage})</h3>
              </div>
              <div className="relative">
                <textarea
                  value={targetCode}
                  readOnly
                  className="w-full h-96 p-4 bg-gray-800 text-gray-100 font-mono text-sm resize-none border-none outline-none"
                  placeholder={isConverting ? t('convertingPlaceholder') : t('convertedCodePlaceholder')}
                />
                {isConverting && (
                  <div className="absolute inset-0 bg-gray-800 bg-opacity-75 flex items-center justify-center">
                    <Loader2 className="w-8 h-8 animate-spin text-blue-400" />
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Footer */}
          <div className="mt-8 text-center text-gray-400 text-sm">
            <p>{t('footerText1')}</p>
            <p className="mt-1">{t('footerText2')}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

// Custom Language Dropdown Component
const LanguageDropdown = ({ value, onChange, languages, placeholder }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const dropdownRef = useRef(null);

  const filteredLanguages = languages.filter(lang =>
    lang.toLowerCase().includes(searchTerm.toLowerCase())
  );

  useEffect(() => {
    const handleClickOutside = (event) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target)) {
        setIsOpen(false);
        setSearchTerm('');
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleLanguageSelect = (language) => {
    onChange(language);
    setIsOpen(false);
    setSearchTerm('');
  };

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center justify-between gap-2 bg-gray-700 hover:bg-gray-600 px-4 py-3 rounded-lg min-w-48 text-left border border-gray-600"
      >
        <span className="text-gray-200">{value || placeholder}</span>
        <ChevronDown className={`w-5 h-5 text-gray-400 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && (
        <div className="absolute top-full left-0 right-0 mt-1 bg-gray-700 border border-gray-600 rounded-lg shadow-lg z-50 max-h-64 overflow-hidden">
          <div className="p-2 border-b border-gray-600">
            <input
              type="text"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder={t('searchLanguagesPlaceholder')}
              className="w-full px-3 py-2 bg-gray-800 text-gray-200 rounded border border-gray-600 text-sm outline-none focus:border-blue-500"
              autoFocus
            />
          </div>
          <div className="max-h-48 overflow-y-auto">
            {filteredLanguages.length > 0 ? (
              filteredLanguages.map((language) => (
                <button
                  key={language}
                  onClick={() => handleLanguageSelect(language)}
                  className={`w-full text-left px-4 py-2 hover:bg-gray-600 transition-colors ${
                    value === language ? 'bg-blue-600 text-white' : 'text-gray-200'
                  }`}
                >
                  {language}
                </button>
              ))
            ) : (
              <div className="px-4 py-2 text-gray-400 text-sm">{t('noLanguagesFound')}</div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default CodeVerter;
