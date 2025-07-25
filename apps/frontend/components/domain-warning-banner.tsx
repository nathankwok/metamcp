"use client";

import { useEffect, useState } from "react";

import { getAppUrl } from "@/lib/env";

interface DomainWarningBannerProps {
  className?: string;
}

export function DomainWarningBanner({
  className = "",
}: DomainWarningBannerProps) {
  const [showDomainWarning, setShowDomainWarning] = useState(false);
  const [domainInfo, setDomainInfo] = useState<{
    current: string;
    expected: string;
  } | null>(null);

  // Function to check domain validation
  const checkDomainValidation = () => {
    try {
      const configuredAppUrl = getAppUrl();
      const currentOrigin = window.location.origin;
      const configuredOrigin = new URL(configuredAppUrl).origin;

      // Domain validation should pass if we're on the correct frontend domain
      if (currentOrigin !== configuredOrigin) {
        setShowDomainWarning(true);
        setDomainInfo({
          current: currentOrigin,
          expected: configuredOrigin,
        });
        return false;
      }
      setShowDomainWarning(false);
      setDomainInfo(null);
      return true;
    } catch (error) {
      console.error("Error checking domain validation:", error);
      // If we can't check, don't show warning (fail open)
      setShowDomainWarning(false);
      setDomainInfo(null);
      return true;
    }
  };

  // Check domain validation once on load
  useEffect(() => {
    checkDomainValidation();
  }, []);

  const handleDismissWarning = () => {
    setShowDomainWarning(false);
  };

  const handleViewDetails = () => {
    const corsErrorUrl = new URL("/cors-error", window.location.origin);
    corsErrorUrl.searchParams.set(
      "callbackUrl",
      window.location.pathname + window.location.search,
    );
    window.location.href = corsErrorUrl.toString();
  };

  if (!showDomainWarning || !domainInfo) {
    return null;
  }

  return (
    <div
      className={`bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6 ${className}`}
    >
      <div className="flex items-start">
        <div className="flex-shrink-0">
          <svg
            className="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fillRule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clipRule="evenodd"
            />
          </svg>
        </div>
        <div className="ml-3 flex-1">
          <h3 className="text-sm font-medium text-yellow-800">
            Domain Mismatch Warning
          </h3>
          <div className="mt-2 text-sm text-yellow-700">
            <p>
              You&apos;re accessing this app from{" "}
              <span className="font-mono font-semibold">
                {domainInfo.current}
              </span>{" "}
              but it&apos;s configured for{" "}
              <span className="font-mono font-semibold">
                {domainInfo.expected}
              </span>
              .
            </p>
          </div>
          <div className="mt-3 flex space-x-2">
            <button
              onClick={handleViewDetails}
              className="text-sm text-yellow-800 underline hover:text-yellow-900"
            >
              View Details
            </button>
            <button
              onClick={handleDismissWarning}
              className="text-sm text-yellow-600 hover:text-yellow-700"
            >
              Dismiss
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
