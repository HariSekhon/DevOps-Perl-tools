<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
<xsl:output method="html"/>
<xsl:template match="configuration">
<xsl:for-each select="property">
<xsl:value-of select="name"/> <xsl:text><![CDATA[=]]></xsl:text>
<xsl:value-of select="value"/>
<xsl:text>
</xsl:text>
</xsl:for-each>
</xsl:template>
</xsl:stylesheet>
